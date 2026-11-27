package disk

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/go-jose/go-jose/v3/jwt"
	"github.com/spiffe/go-spiffe/v2/spiffeid"
	"github.com/spiffe/go-spiffe/v2/svid/jwtsvid"
	"github.com/stretchr/testify/require"
)

func TestWriteJWTSVIDConcurrentAtomicRead(t *testing.T) {
	spiffeID := spiffeid.RequireFromString("spiffe://nuage/host/atelier/bot")
	key, err := ecdsa.GenerateKey(elliptic.P384(), rand.Reader)
	require.NoError(t, err)

	mkSVID := func(aud string) (*jwtsvid.SVID, string) {
		tok := generateToken(t, jwt.Claims{
			Subject:  spiffeID.String(),
			Issuer:   testJWTIssuer,
			Expiry:   jwt.NewNumericDate(time.Now().Add(5 * time.Minute)),
			Audience: []string{aud},
			IssuedAt: jwt.NewNumericDate(time.Now()),
		}, key, "key")
		svid, err := jwtsvid.ParseInsecure(tok, []string{aud})
		require.NoError(t, err)
		return svid, tok
	}

	svidA, tokA := mkSVID("monitoring-pwa-a")
	svidB, tokB := mkSVID("monitoring-pwa-b")

	tempDir := t.TempDir()
	jwtDisk := NewJWT(JWTConfig{
		Dir:          tempDir,
		SVIDFileMode: 0640,
	})
	const fileName = "monitoring-pwa.jwt"
	targetPath := filepath.Join(tempDir, fileName)

	require.NoError(t, jwtDisk.WriteJWTSVID([]*jwtsvid.SVID{svidA}, fileName))

	var done atomic.Bool
	var wg sync.WaitGroup
	errCh := make(chan string, 16)

	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for !done.Load() {
				b, err := os.ReadFile(targetPath)
				if err != nil {
					select {
					case errCh <- err.Error():
					default:
					}
					return
				}
				s := string(b)
				if s != tokA && s != tokB {
					select {
					case errCh <- "observed partial or unexpected JWT content":
					default:
					}
					return
				}
			}
		}()
	}

	for i := range 200 {
		svid := svidA
		if i%2 == 1 {
			svid = svidB
		}
		require.NoError(t, jwtDisk.WriteJWTSVID([]*jwtsvid.SVID{svid}, fileName))
	}
	done.Store(true)
	wg.Wait()

	close(errCh)
	for msg := range errCh {
		t.Fatal(msg)
	}
}
