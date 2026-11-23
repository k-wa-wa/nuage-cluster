"""mvsctl.py の純粋ロジックおよび JCL / カードデッキ生成のユニットテスト。"""

import tempfile
import unittest
from pathlib import Path
from unittest import mock

import mvsctl


class TestJobResult(unittest.TestCase):
    def test_normal_completion(self):
        output = "IEF142I MYJOB STEP1 - STEP WAS EXECUTED - COND CODE 0000\n"
        result = mvsctl.JobResult("MYJOB", output)
        self.assertEqual(result.cond_codes, [0])
        self.assertEqual(result.abends, [])
        self.assertFalse(result.jcl_error)
        self.assertEqual(result.max_cc, 0)
        self.assertTrue(result.ok(0))
        self.assertEqual(result.summary(), "MYJOB: MAXCC=0000")

    def test_multiple_steps_max_cc(self):
        output = (
            "IEF142I MYJOB STEP1 - STEP WAS EXECUTED - COND CODE 0000\n"
            "IEF142I MYJOB STEP2 - STEP WAS EXECUTED - COND CODE 0004\n"
            "IEF142I MYJOB STEP3 - STEP WAS EXECUTED - COND CODE 0002\n"
        )
        result = mvsctl.JobResult("MYJOB", output)
        self.assertEqual(result.cond_codes, [0, 4, 2])
        self.assertEqual(result.max_cc, 4)
        self.assertFalse(result.ok(0))
        self.assertTrue(result.ok(4))
        self.assertEqual(result.summary(), "MYJOB: MAXCC=0004")

    def test_abend_single_and_multiple(self):
        output_single = (
            "IEF142I MYJOB STEP1 - STEP WAS EXECUTED - COND CODE 0000\n"
            "IEF450I MYJOB STEP2 - ABEND S0C7 U0000\n"
        )
        result_single = mvsctl.JobResult("MYJOB", output_single)
        self.assertEqual(result_single.abends, ["S0C7"])
        self.assertFalse(result_single.ok(9999))
        self.assertEqual(result_single.summary(), "MYJOB: ABEND S0C7")

        output_multi = (
            "IEF450I MYJOB STEP1 - ABEND S0C7 U0000\n"
            "IEF450I MYJOB STEP2 - ABEND U0016\n"
        )
        result_multi = mvsctl.JobResult("MYJOB", output_multi)
        self.assertEqual(result_multi.abends, ["S0C7", "U0016"])
        self.assertFalse(result_multi.ok(9999))
        self.assertEqual(result_multi.summary(), "MYJOB: ABEND S0C7 U0016")

    def test_jcl_error_ief452i_and_ief453i(self):
        output_452 = (
            "IEF142I MYJOB STEP1 - STEP WAS EXECUTED - COND CODE 0000\n"
            "IEF452I MYJOB - JOB NOT RUN - JCL ERROR\n"
        )
        result_452 = mvsctl.JobResult("MYJOB", output_452)
        self.assertTrue(result_452.jcl_error)
        self.assertFalse(result_452.ok(0))
        self.assertEqual(result_452.summary(), "MYJOB: JCL ERROR")

        output_453 = "IEF453I MYJOB - JOB FAILED - JCL ERROR\n"
        result_453 = mvsctl.JobResult("MYJOB", output_453)
        self.assertTrue(result_453.jcl_error)
        self.assertFalse(result_453.ok(0))
        self.assertEqual(result_453.summary(), "MYJOB: JCL ERROR")

    def test_no_cond_codes(self):
        result = mvsctl.JobResult("MYJOB", "$HASP395 MYJOB ENDED\n")
        self.assertEqual(result.cond_codes, [])
        self.assertEqual(result.max_cc, 0)
        self.assertFalse(result.ok(0))
        self.assertFalse(result.ok(4))
        self.assertEqual(result.summary(), "MYJOB: MAXCC=0000")

    def test_summary_priority_jcl_error_over_abend(self):
        output = (
            "IEF450I MYJOB STEP1 - ABEND S0C7\n"
            "IEF453I MYJOB - JOB FAILED - JCL ERROR\n"
        )
        result = mvsctl.JobResult("MYJOB", output)
        self.assertTrue(result.jcl_error)
        self.assertEqual(result.abends, ["S0C7"])
        self.assertEqual(result.summary(), "MYJOB: JCL ERROR")


class TestJobnameOf(unittest.TestCase):
    def test_valid_jobnames(self):
        cases = [
            ("//A JOB \n", "A"),
            ("//JOB12345 JOB (NUAGE),'DESC',CLASS=A\n", "JOB12345"),
            ("//@12#34$5 JOB CLASS=A\n", "@12#34$5"),
            ("//#TEST JOB\tCLASS=A\n", "#TEST"),
            ("//$A JOB \n", "$A"),
        ]
        for jcl, expected in cases:
            with self.subTest(jcl=jcl):
                self.assertEqual(mvsctl.jobname_of(jcl), expected)

    def test_invalid_first_line_raises(self):
        invalid_cases = [
            "//* COMMENT\n//VALID JOB \n",
            "",
            "//STEP1 EXEC PGM=IEFBR14\n",
            "//TOOLONG99 JOB \n",
            "//lower JOB \n",
            "//MixCase JOB \n",
            "//1DIGIT JOB \n",
        ]
        for jcl in invalid_cases:
            with self.subTest(jcl=jcl):
                with self.assertRaises(SystemExit):
                    mvsctl.jobname_of(jcl)


class TestCheckColumns(unittest.TestCase):
    def test_exact_limit_passes(self):
        mvsctl.check_columns(["A" * mvsctl.JCL_MAX_COLUMNS], mvsctl.JCL_MAX_COLUMNS, "JCL")
        mvsctl.check_columns(["B" * mvsctl.DATA_MAX_COLUMNS], mvsctl.DATA_MAX_COLUMNS, "DATA")

    def test_over_limit_raises(self):
        with self.assertRaises(SystemExit):
            mvsctl.check_columns(
                ["OK", "A" * (mvsctl.JCL_MAX_COLUMNS + 1)],
                mvsctl.JCL_MAX_COLUMNS,
                "JCL",
            )
        with self.assertRaises(SystemExit):
            mvsctl.check_columns(
                ["B" * (mvsctl.DATA_MAX_COLUMNS + 1)],
                mvsctl.DATA_MAX_COLUMNS,
                "DATA",
            )


class TestLoadMembers(unittest.TestCase):
    def test_loads_valid_members_and_ignores_hidden_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            dsn_dir = root / "SYS1.PARMLIB"
            dsn_dir.mkdir()
            (dsn_dir / "COMMND00").write_text("COM='S JES2'\n", encoding="ascii")
            (dsn_dir / "@#1$AB").write_text("VALUE=1\n", encoding="ascii")
            (dsn_dir / ".DS_Store").write_text("ignored", encoding="ascii")
            (dsn_dir / ".gitkeep").write_text("", encoding="ascii")

            members = mvsctl.load_members(root)
            self.assertEqual(
                members,
                {
                    ("SYS1.PARMLIB", "@#1$AB"): "VALUE=1\n",
                    ("SYS1.PARMLIB", "COMMND00"): "COM='S JES2'\n",
                },
            )

    def test_invalid_member_names_raise(self):
        invalid_names = ["lower", "TOOLONG99", "1START", "BAD-NAME", "BAD.NAME"]
        for name in invalid_names:
            with self.subTest(name=name):
                with tempfile.TemporaryDirectory() as tmp:
                    dsn_dir = Path(tmp) / "NUAGE.CNTL"
                    dsn_dir.mkdir()
                    (dsn_dir / name).write_text("OK\n", encoding="ascii")
                    with self.assertRaises(SystemExit):
                        mvsctl.load_members(tmp)

    def test_valid_special_chars_and_length_bounds(self):
        with tempfile.TemporaryDirectory() as tmp:
            dsn_dir = Path(tmp) / "NUAGE.CNTL"
            dsn_dir.mkdir()
            (dsn_dir / "A").write_text("1\n", encoding="ascii")
            (dsn_dir / "@#$12345").write_text("8\n", encoding="ascii")

            members = mvsctl.load_members(tmp)
            self.assertIn(("NUAGE.CNTL", "A"), members)
            self.assertIn(("NUAGE.CNTL", "@#$12345"), members)

    def test_column_limit_72_passes_and_73_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            dsn_dir = Path(tmp) / "NUAGE.CNTL"
            dsn_dir.mkdir()
            member = dsn_dir / "MEM72"
            member.write_text("X" * mvsctl.DATA_MAX_COLUMNS + "\n", encoding="ascii")
            members = mvsctl.load_members(tmp)
            self.assertEqual(members[("NUAGE.CNTL", "MEM72")], "X" * 72 + "\n")

            member.write_text("X" * (mvsctl.DATA_MAX_COLUMNS + 1) + "\n", encoding="ascii")
            with self.assertRaises(SystemExit):
                mvsctl.load_members(tmp)

    def test_forbidden_prefix_lines_and_allowed_inline(self):
        for bad_line in ("./ ADD NAME=X\n", "$$\n"):
            with self.subTest(bad_line=bad_line):
                with tempfile.TemporaryDirectory() as tmp:
                    dsn_dir = Path(tmp) / "NUAGE.CNTL"
                    dsn_dir.mkdir()
                    (dsn_dir / "BAD").write_text(f"OK\n{bad_line}", encoding="ascii")
                    with self.assertRaises(SystemExit):
                        mvsctl.load_members(tmp)

        with tempfile.TemporaryDirectory() as tmp:
            dsn_dir = Path(tmp) / "NUAGE.CNTL"
            dsn_dir.mkdir()
            (dsn_dir / "GOOD").write_text("  ./ INLINE\nFOO $$ BAR\n", encoding="ascii")
            members = mvsctl.load_members(tmp)
            self.assertEqual(members[("NUAGE.CNTL", "GOOD")], "  ./ INLINE\nFOO $$ BAR\n")

    def test_normalizes_line_endings_and_trailing_newline(self):
        with tempfile.TemporaryDirectory() as tmp:
            dsn_dir = Path(tmp) / "NUAGE.CNTL"
            dsn_dir.mkdir()
            (dsn_dir / "NOEOF").write_bytes(b"LINE1\nLINE2")
            (dsn_dir / "CRLF").write_bytes(b"LINE1\r\nLINE2\r\n")

            members = mvsctl.load_members(tmp)
            self.assertEqual(members[("NUAGE.CNTL", "NOEOF")], "LINE1\nLINE2\n")
            self.assertEqual(members[("NUAGE.CNTL", "CRLF")], "LINE1\nLINE2\n")


class TestCreateSteps(unittest.TestCase):
    def _assert_jcl_lines_fit(self, jcl):
        for line in jcl.splitlines():
            if line.startswith("//"):
                self.assertLessEqual(len(line), mvsctl.JCL_MAX_COLUMNS, line)

    def test_po_default_and_explicit(self):
        ds_base = {
            "dsn": "NUAGE.TEST.PO",
            "unit": "3390",
            "volser": "PUB000",
            "space": "(TRK,(5,5,10))",
            "dcb": "(RECFM=FB,LRECL=80,BLKSIZE=3120)",
        }
        expected = (
            "//C01      EXEC PGM=IEFBR14\n"
            "//DS       DD DSN=NUAGE.TEST.PO,DISP=(NEW,CATLG),\n"
            "//             UNIT=3390,VOL=SER=PUB000,\n"
            "//             SPACE=(TRK,(5,5,10)),\n"
            "//             DCB=(RECFM=FB,LRECL=80,BLKSIZE=3120)\n"
        )
        default_out = mvsctl.create_steps("C01", ds_base)
        explicit_out = mvsctl.create_steps("C01", {**ds_base, "type": "PO"})
        self.assertEqual(default_out, expected)
        self.assertEqual(explicit_out, expected)
        self._assert_jcl_lines_fit(explicit_out)

    def test_ps(self):
        ds = {
            "type": "PS",
            "dsn": "NUAGE.TEST.PS",
            "unit": "3390",
            "volser": "PUB000",
            "space": "(TRK,(5,1))",
            "dcb": "(RECFM=FB,LRECL=80,BLKSIZE=3120)",
        }
        expected = (
            "//C02      EXEC PGM=IEBGENER\n"
            "//SYSPRINT DD SYSOUT=*\n"
            "//SYSIN    DD DUMMY\n"
            "//SYSUT1   DD DUMMY,DCB=(RECFM=FB,LRECL=80,BLKSIZE=3120)\n"
            "//SYSUT2   DD DSN=NUAGE.TEST.PS,DISP=(NEW,CATLG),\n"
            "//             UNIT=3390,VOL=SER=PUB000,\n"
            "//             SPACE=(TRK,(5,1)),\n"
            "//             DCB=(RECFM=FB,LRECL=80,BLKSIZE=3120)\n"
        )
        out = mvsctl.create_steps("C02", ds)
        self.assertEqual(out, expected)
        self._assert_jcl_lines_fit(out)

    def test_gdg(self):
        ds = {
            "type": "GDG",
            "dsn": "NUAGE.TEST.GDG",
            "limit": 5,
            "unit": "3390",
            "volser": "PUB000",
            "space": "(TRK,(5,1))",
            "model": "NUAGE.MODEL.DSCB",
            "dcb": "(RECFM=FB,LRECL=80,BLKSIZE=3120)",
        }
        expected = (
            "//C03D     EXEC PGM=IDCAMS\n"
            "//SYSPRINT DD SYSOUT=*\n"
            "//SYSIN    DD *\n"
            "  DEFINE GDG (NAME(NUAGE.TEST.GDG) LIMIT(5) -\n"
            "              SCRATCH NOEMPTY)\n"
            "/*\n"
            "//C03G     EXEC PGM=IEBGENER\n"
            "//SYSPRINT DD SYSOUT=*\n"
            "//SYSIN    DD DUMMY\n"
            "//SYSUT1   DD DUMMY,DCB=(RECFM=FB,LRECL=80,BLKSIZE=3120)\n"
            "//SYSUT2   DD DSN=NUAGE.TEST.GDG(+1),DISP=(NEW,CATLG),\n"
            "//             UNIT=3390,VOL=SER=PUB000,\n"
            "//             SPACE=(TRK,(5,1)),\n"
            "//             DCB=(NUAGE.MODEL.DSCB,\n"
            "//             RECFM=FB,LRECL=80,BLKSIZE=3120)\n"
        )
        out = mvsctl.create_steps("C03", ds)
        self.assertEqual(out, expected)
        self._assert_jcl_lines_fit(out)

    def test_alias(self):
        ds = {
            "type": "ALIAS",
            "dsn": "NUAGE",
            "catalog": "SYS1.UCAT.MVS",
        }
        expected = (
            "//C04      EXEC PGM=IDCAMS\n"
            "//SYSPRINT DD SYSOUT=*\n"
            "//SYSIN    DD *\n"
            "  DEFINE ALIAS (NAME(NUAGE) RELATE(SYS1.UCAT.MVS))\n"
            "/*\n"
        )
        out = mvsctl.create_steps("C04", ds)
        self.assertEqual(out, expected)
        self._assert_jcl_lines_fit(out)

    def test_unknown_type_raises(self):
        with self.assertRaises(SystemExit):
            mvsctl.create_steps(
                "C05",
                {
                    "type": "VSAM",
                    "dsn": "NUAGE.BAD",
                    "unit": "3390",
                    "volser": "PUB000",
                    "space": "(TRK,(1,1))",
                },
            )


class TestBuildUpdateJob(unittest.TestCase):
    def test_multiple_datasets_and_members(self):
        members = {
            ("NUAGE.PARM", "MEM2"): "KEY=B\n",
            ("NUAGE.CNTL", "JOB1"): "//MYJOB JOB \n",
            ("NUAGE.PARM", "MEM1"): "KEY=A\n",
        }
        jcl = mvsctl.build_update_job(members, [], "HERC01", "PASS123")

        expected = (
            "//MVSCONF  JOB (NUAGE),'NUAGE MVS-CONFIG',CLASS=A,MSGCLASS=A,\n"
            "//             MSGLEVEL=(1,1),USER=HERC01,PASSWORD=PASS123\n"
            "//STEP1    EXEC PGM=IEBUPDTE,PARM=NEW\n"
            "//SYSPRINT DD SYSOUT=*\n"
            "//SYSUT2   DD DSN=NUAGE.CNTL,DISP=SHR\n"
            "//SYSIN    DD DATA,DLM=$$\n"
            "./ ADD NAME=JOB1,LIST=ALL\n"
            "//MYJOB JOB \n"
            "./ ENDUP\n"
            "$$\n"
            "//STEP2    EXEC PGM=IEBUPDTE,PARM=NEW\n"
            "//SYSPRINT DD SYSOUT=*\n"
            "//SYSUT2   DD DSN=NUAGE.PARM,DISP=SHR\n"
            "//SYSIN    DD DATA,DLM=$$\n"
            "./ ADD NAME=MEM2,LIST=ALL\n"
            "KEY=B\n"
            "./ ADD NAME=MEM1,LIST=ALL\n"
            "KEY=A\n"
            "./ ENDUP\n"
            "$$\n"
            "//\n"
        )
        self.assertEqual(jcl, expected)
        for line in jcl.splitlines():
            if line.startswith("//"):
                self.assertLessEqual(len(line), mvsctl.JCL_MAX_COLUMNS, line)

    def test_datasets_and_migrations_placed_after_job_card(self):
        members = {("NUAGE.CNTL", "M1"): "DATA\n"}
        datasets = [
            {
                "type": "PO",
                "dsn": "NUAGE.CNTL",
                "unit": "3390",
                "volser": "PUB000",
                "space": "(TRK,(5,5,5))",
                "dcb": "(RECFM=FB,LRECL=80,BLKSIZE=3120)",
            }
        ]
        migrations = "//MIGRATE  EXEC PGM=IDCAMS\n"
        jcl = mvsctl.build_update_job(members, datasets, "HERC01", "PASS123", migrations=migrations)

        job_card = mvsctl.job_card("MVSCONF", "NUAGE MVS-CONFIG", "HERC01", "PASS123")
        create_part = mvsctl.create_steps("C01", datasets[0])
        self.assertTrue(jcl.startswith(job_card + migrations + create_part + "//STEP1"))
        self.assertTrue(jcl.endswith("//\n"))
        for line in jcl.splitlines():
            if line.startswith("//"):
                self.assertLessEqual(len(line), mvsctl.JCL_MAX_COLUMNS, line)


class TestWaitForJob(unittest.TestCase):
    def test_ignores_output_before_offset(self):
        with tempfile.TemporaryDirectory() as tmp:
            printer = Path(tmp) / "prt00e.txt"
            before = (
                "****A START JOB   10 MYJOB   \n"
                "JOB   10 $HASP395 MYJOB    ENDED\n"
                "****A END   JOB   10 MYJOB   \n"
                "****A START JOB   11 OTHER   \n"
                "JOB   11 $HASP395 OTHER    ENDED\n"
                "****A END   JOB   11 OTHER   \n"
            ).encode("ascii")
            after = (
                "****A START JOB   12 MYJOB   \n"
                "IEF142I MYJOB STEP1 - COND CODE 0000\n"
                "JOB   12 $HASP395 MYJOB    ENDED\n"
                "****A END   JOB   12 MYJOB   \n"
            ).encode("ascii")
            printer.write_bytes(before + after)

            with (
                mock.patch.object(mvsctl, "PRINTER", printer),
                mock.patch("mvsctl.time.monotonic", side_effect=[0.0, 1.0]),
            ):
                out = mvsctl.wait_for_job("MYJOB", len(before), timeout=10)

            self.assertEqual(out, after.decode("ascii"))
            self.assertNotIn("JOB   10", out)
            self.assertNotIn("OTHER", out)

    def test_waits_past_dynamic_sysout_end_until_job_log_end(self):
        with tempfile.TemporaryDirectory() as tmp:
            printer = Path(tmp) / "prt00e.txt"
            content = (
                "****A START JOB  123 MYJOB   \n"
                "IEBCOPY MESSAGES\n"
                "****A END   JOB  123 MYJOB   \n"
                "\f****A START JOB  123 MYJOB   \n"
                "IEF142I MYJOB STEP1 - COND CODE 0000\n"
                "JOB  123 $HASP395 MYJOB    ENDED\n"
                "****A END   JOB  123 MYJOB   \n"
                "TRAILING NOISE\n"
            ).encode("ascii")
            printer.write_bytes(content)

            with (
                mock.patch.object(mvsctl, "PRINTER", printer),
                mock.patch("mvsctl.time.monotonic", side_effect=[0.0, 1.0]),
            ):
                out = mvsctl.wait_for_job("MYJOB", 0, timeout=10)

            expected = (
                "****A START JOB  123 MYJOB   \n"
                "IEBCOPY MESSAGES\n"
                "****A END   JOB  123 MYJOB   \n"
                "\n****A START JOB  123 MYJOB   \n"
                "IEF142I MYJOB STEP1 - COND CODE 0000\n"
                "JOB  123 $HASP395 MYJOB    ENDED\n"
                "****A END   JOB  123 MYJOB   \n"
            )
            self.assertEqual(out, expected)

    def test_extracts_job_ended_with_ief452i(self):
        with tempfile.TemporaryDirectory() as tmp:
            printer = Path(tmp) / "prt00e.txt"
            content = (
                "****A START JOB  456 MYJOB   \n"
                "JOB  456 IEF452I MYJOB    - JOB NOT RUN - JCL ERROR\n"
                "****A END   JOB  456 MYJOB   \n"
            ).encode("ascii")
            printer.write_bytes(content)

            with (
                mock.patch.object(mvsctl, "PRINTER", printer),
                mock.patch("mvsctl.time.monotonic", side_effect=[0.0, 1.0]),
            ):
                out = mvsctl.wait_for_job("MYJOB", 0, timeout=10)

            self.assertEqual(out, content.decode("ascii"))

    def test_restarts_from_zero_when_printer_truncated(self):
        with tempfile.TemporaryDirectory() as tmp:
            printer = Path(tmp) / "prt00e.txt"
            content = (
                "****A START JOB  789 MYJOB   \n"
                "JOB  789 $HASP395 MYJOB    ENDED\n"
                "****A END   JOB  789 MYJOB   \n"
            ).encode("ascii")
            printer.write_bytes(content)

            with (
                mock.patch.object(mvsctl, "PRINTER", printer),
                mock.patch("mvsctl.time.monotonic", side_effect=[0.0, 1.0]),
            ):
                out = mvsctl.wait_for_job("MYJOB", offset=len(content) + 1000, timeout=10)

            self.assertEqual(out, content.decode("ascii"))

    def test_timeout_raises_system_exit(self):
        with tempfile.TemporaryDirectory() as tmp:
            printer = Path(tmp) / "prt00e.txt"
            printer.write_bytes(b"")

            with (
                mock.patch.object(mvsctl, "PRINTER", printer),
                mock.patch("mvsctl.time.monotonic", side_effect=[0.0, 1.0, 10.0]),
                mock.patch("mvsctl.time.sleep") as mock_sleep,
            ):
                with self.assertRaises(SystemExit):
                    mvsctl.wait_for_job("MYJOB", 0, timeout=5)
                mock_sleep.assert_called_once_with(2)


class TestKicksInstallDeck(unittest.TestCase):
    def _cards_from_deck(self, deck, xmi):
        idx = deck.index(xmi)
        before_xmi = deck[:idx]
        after_xmi = deck[idx + len(xmi):]
        jcl_bytes = before_xmi + after_xmi
        self.assertEqual(len(jcl_bytes) % 80, 0)
        return [
            jcl_bytes[i:i + 80].decode("cp037").rstrip()
            for i in range(0, len(jcl_bytes), 80)
        ]

    def test_non_multiple_of_80_raises(self):
        for bad_len in (79, 81):
            with self.subTest(bad_len=bad_len):
                with self.assertRaises(SystemExit):
                    mvsctl.kicks_install_deck(b"\x00" * bad_len, "HERC01", "PASS123")

    def test_default_dlm_and_embedded_xmi(self):
        xmi = b"\x01\x02" + b"\xaa" * 78 + b"\x03\x04" + b"\xbb" * 78
        deck = mvsctl.kicks_install_deck(xmi, "HERC01", "PASS123")

        self.assertEqual(len(deck) % 80, 0)
        self.assertIn(xmi, deck)

        cards = self._cards_from_deck(deck, xmi)
        self.assertIn("//SYSUT1   DD DATA,DLM=$$", cards)
        self.assertIn("$$", cards)
        for line in cards:
            self.assertNotIn("@DLM@", line)
            self.assertNotIn("@@XMI@@", line)
            if line.startswith("//"):
                self.assertLessEqual(len(line), mvsctl.JCL_MAX_COLUMNS, line)

    def test_dlm_avoids_dollar_and_hash_collisions(self):
        xmi_dollar = "$$".encode("cp037") + b"\x00" * 78
        deck_hash = mvsctl.kicks_install_deck(xmi_dollar, "HERC01", "PASS123")
        cards_hash = self._cards_from_deck(deck_hash, xmi_dollar)
        self.assertIn("//SYSUT1   DD DATA,DLM=##", cards_hash)
        self.assertIn("##", cards_hash)

        xmi_both = "$$".encode("cp037") + b"\x00" * 78 + "##".encode("cp037") + b"\x11" * 78
        deck_at = mvsctl.kicks_install_deck(xmi_both, "HERC01", "PASS123")
        cards_at = self._cards_from_deck(deck_at, xmi_both)
        self.assertIn("//SYSUT1   DD DATA,DLM=@@", cards_at)
        self.assertIn("@@", cards_at)
        for line in cards_at:
            self.assertNotIn("@DLM@", line)
            self.assertNotIn("@@XMI@@", line)
            if line.startswith("//"):
                self.assertLessEqual(len(line), mvsctl.JCL_MAX_COLUMNS, line)


if __name__ == "__main__":
    unittest.main()
