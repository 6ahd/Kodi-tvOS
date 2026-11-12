// SPDX-License-Identifier: GPL-3.0-only
//
// The NuvioTV Usenet engine as a library, for systems where an app may not start a second
// program (tvOS). It is the same server as cmd/nuvio-usenet, with the same start record;
// only the way in differs: two C calls instead of stdin and stdout.
//
//	int  NuvioUsenetStart(const char *json)  the start record as JSON; returns the port,
//	                                         or a negative number when it did not start
//	int  NuvioUsenetPort(void)               the port while it runs, 0 otherwise
//	void NuvioUsenetStop(void)               closes every session and the listener
//
// Added for Dex Hub's Apple TV app, 11 November 2026. Licence: GPL-3.0, as the engine.
package main

import "C"

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"net"
	"net/http"
	"runtime/debug"
	"sync"
	"time"

	"github.com/NuvioMedia/NuvioTV/native/usenet/internal/engine"
)

var (
	mu      sync.Mutex
	stop    context.CancelFunc
	done    chan struct{}
	port    int
	running string // the token of the server that runs
)

//export NuvioUsenetStart
func NuvioUsenetStart(config *C.char) C.int {
	var init struct {
		Token        string   `json:"token"`
		Certificates []string `json:"certificates"`
		MemoryMiB    int64    `json:"memoryMiB"`
		NZBCacheDir  string   `json:"nzbCacheDir"`
	}
	if err := json.Unmarshal([]byte(C.GoString(config)), &init); err != nil {
		return -1
	}
	if len(init.Token) < 32 {
		return -2
	}
	mu.Lock()
	defer mu.Unlock()
	if stop != nil {
		if running == init.Token {
			return C.int(port)
		}
		stopLocked()
	}
	limit := init.MemoryMiB
	if limit < 64 {
		limit = 128
	}
	if limit > 512 {
		limit = 512
	}
	debug.SetMemoryLimit(limit << 20)
	roots, _ := x509.SystemCertPool()
	if roots == nil {
		roots = x509.NewCertPool()
	}
	for _, pem := range init.Certificates {
		roots.AppendCertsFromPEM([]byte(pem))
	}
	ctx, cancel := context.WithCancel(context.Background())
	transport := &http.Transport{Proxy: http.ProxyFromEnvironment, TLSClientConfig: &tls.Config{RootCAs: roots, MinVersion: tls.VersionTLS12}, ResponseHeaderTimeout: 30 * time.Second, IdleConnTimeout: 60 * time.Second}
	client := &http.Client{Transport: transport, Timeout: 2 * time.Minute}
	app := engine.NewServer(ctx, init.Token, roots, client)
	app.SetNZBCacheDir(init.NZBCacheDir)
	ln, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		app.Close()
		cancel()
		return -3
	}
	srv := &http.Server{Handler: app, ReadHeaderTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 32 << 10, BaseContext: func(net.Listener) context.Context { return ctx }}
	finished := make(chan struct{})
	go func() { <-ctx.Done(); srv.Close() }()
	go func() {
		srv.Serve(ln)
		app.Close()
		transport.CloseIdleConnections()
		close(finished)
	}()
	stop, done, port, running = cancel, finished, ln.Addr().(*net.TCPAddr).Port, init.Token
	return C.int(port)
}

//export NuvioUsenetPort
func NuvioUsenetPort() C.int {
	mu.Lock()
	defer mu.Unlock()
	if stop == nil {
		return 0
	}
	return C.int(port)
}

//export NuvioUsenetStop
func NuvioUsenetStop() {
	mu.Lock()
	defer mu.Unlock()
	stopLocked()
}

func stopLocked() {
	if stop == nil {
		return
	}
	stop()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
	}
	stop, done, port, running = nil, nil, 0, ""
}

func main() {}
