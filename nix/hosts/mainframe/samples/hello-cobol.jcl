//HELLOCOB JOB (NUAGE),'HELLO COBOL',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1)
//*
//* COBOL をコンパイルして、そのまま実行する (COBUCG = Compile and Go)
//* 実行結果は 1403 プリンタ (/var/lib/mainframe/printers/prt00e.txt) に出る
//*
//HELLO    EXEC COBUCG
//COB.SYSIN DD *
       IDENTIFICATION DIVISION.
       PROGRAM-ID. HELLO.
       ENVIRONMENT DIVISION.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       77  A        PIC 9V9 VALUE 0.1.
       77  B        PIC 9V9 VALUE 0.2.
       77  C        PIC 9V9.
       77  C-EDIT   PIC 9.9.
       PROCEDURE DIVISION.
           DISPLAY 'HELLO, NUAGE MAINFRAME'.
           ADD A B GIVING C.
           MOVE C TO C-EDIT.
           DISPLAY '0.1 + 0.2 = ' C-EDIT.
           STOP RUN.
/*
//GO.SYSOUT DD SYSOUT=*
//
