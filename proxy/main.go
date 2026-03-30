package main

import (
	"bufio"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// DomainPolicy describes which HTTP methods are allowed for a domain.
type DomainPolicy struct {
	AllowAll bool
	Methods  map[string]bool
}

// Config maps domain names to their policies. The "*" key is the default policy.
type Config map[string]DomainPolicy

const maxURLBytes = 8192

// directTransport bypasses ProxyFromEnvironment so the proxy itself
// doesn't try to route through another proxy on the host.
var directTransport = &http.Transport{
	Proxy: nil,
}

func loadConfig(path string) (Config, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	cfg := make(Config)
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) != 2 {
			continue
		}
		domain := strings.ToLower(strings.TrimSpace(parts[0]))
		methods := strings.TrimSpace(parts[1])
		if methods == "*" {
			cfg[domain] = DomainPolicy{AllowAll: true}
		} else {
			m := make(map[string]bool)
			for _, method := range strings.Split(methods, ",") {
				method = strings.TrimSpace(strings.ToUpper(method))
				if method != "" {
					m[method] = true
				}
			}
			cfg[domain] = DomainPolicy{Methods: m}
		}
	}
	return cfg, sc.Err()
}

// lookupPolicy finds the policy for a host, falling back to the "*" default.
func lookupPolicy(host string, cfg Config) (DomainPolicy, bool) {
	host = strings.ToLower(host)
	if p, ok := cfg[host]; ok {
		return p, true
	}
	for d, p := range cfg {
		if d != "*" && strings.HasSuffix(host, "."+d) {
			return p, true
		}
	}
	if p, ok := cfg["*"]; ok {
		return p, true
	}
	return DomainPolicy{}, false
}

func isDomainAllowed(host string, cfg Config) bool {
	_, ok := lookupPolicy(host, cfg)
	return ok
}

func isMethodAllowed(host, method string, cfg Config) bool {
	policy, ok := lookupPolicy(host, cfg)
	if !ok {
		return false
	}
	if policy.AllowAll {
		return true
	}
	return policy.Methods[strings.ToUpper(method)]
}

func hostOnly(addr string) string {
	h, _, err := net.SplitHostPort(addr)
	if err != nil {
		return addr
	}
	return h
}

// --- CA and certificate minting ---

var (
	caCert    *x509.Certificate
	caKey     *ecdsa.PrivateKey
	certCache sync.Map // hostname -> *tls.Certificate
)

func generateCA() error {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return err
	}
	tmpl := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			CommonName:   "sandbox-proxy CA",
			Organization: []string{"sandbox-proxy"},
		},
		NotBefore:             time.Now().Add(-1 * time.Hour),
		NotAfter:              time.Now().Add(24 * time.Hour),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
		MaxPathLen:            0,
	}
	certDER, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		return err
	}
	cert, err := x509.ParseCertificate(certDER)
	if err != nil {
		return err
	}
	caCert = cert
	caKey = key
	return nil
}

func writeCA(path string) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return pem.Encode(f, &pem.Block{Type: "CERTIFICATE", Bytes: caCert.Raw})
}

func mintCert(hostname string) (*tls.Certificate, error) {
	if cached, ok := certCache.Load(hostname); ok {
		return cached.(*tls.Certificate), nil
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, err
	}
	tmpl := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: hostname},
		NotBefore:    time.Now().Add(-1 * time.Hour),
		NotAfter:     time.Now().Add(24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:     []string{hostname},
	}
	// If hostname looks like an IP, add it as an IP SAN
	if ip := net.ParseIP(hostname); ip != nil {
		tmpl.IPAddresses = []net.IP{ip}
	}
	certDER, err := x509.CreateCertificate(rand.Reader, tmpl, caCert, &key.PublicKey, caKey)
	if err != nil {
		return nil, err
	}
	tlsCert := &tls.Certificate{
		Certificate: [][]byte{certDER},
		PrivateKey:  key,
	}
	certCache.Store(hostname, tlsCert)
	return tlsCert, nil
}

// --- Filtering helpers ---

func isWebSocketUpgrade(req *http.Request) bool {
	for _, v := range req.Header["Upgrade"] {
		for _, token := range strings.Split(v, ",") {
			if strings.EqualFold(strings.TrimSpace(token), "websocket") {
				return true
			}
		}
	}
	return false
}

func requestURLLength(req *http.Request) int {
	return len(req.URL.String())
}

// applyFilters checks method, URL length, and WebSocket restrictions.
// Returns an HTTP status code and reason if blocked, or 0 if allowed.
func applyFilters(req *http.Request, host string, cfg Config) (int, string) {
	if !isMethodAllowed(host, req.Method, cfg) {
		return http.StatusForbidden, "method not allowed"
	}
	if (req.Method == "GET" || req.Method == "HEAD") && requestURLLength(req) > maxURLBytes {
		return http.StatusRequestURITooLong, "URL too long"
	}
	if isWebSocketUpgrade(req) {
		return http.StatusForbidden, "WebSocket not allowed"
	}
	return 0, ""
}

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: sandbox-proxy <config-file> <ca-cert-output-path> [listen-addr]")
		os.Exit(1)
	}
	cfg, err := loadConfig(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, "load config:", err)
		os.Exit(1)
	}

	if err := generateCA(); err != nil {
		fmt.Fprintln(os.Stderr, "generate CA:", err)
		os.Exit(1)
	}
	if err := writeCA(os.Args[2]); err != nil {
		fmt.Fprintln(os.Stderr, "write CA cert:", err)
		os.Exit(1)
	}

	listenAddr := "127.0.0.1"
	if len(os.Args) >= 4 {
		listenAddr = os.Args[3]
	}
	ln, err := net.Listen("tcp", listenAddr+":0")
	if err != nil {
		fmt.Fprintln(os.Stderr, "listen:", err)
		os.Exit(1)
	}
	fmt.Println(ln.Addr().(*net.TCPAddr).Port)
	os.Stdout.Sync()

	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go handle(conn, cfg)
	}
}

func handle(conn net.Conn, cfg Config) {
	defer conn.Close()
	br := bufio.NewReader(conn)
	req, err := http.ReadRequest(br)
	if err != nil {
		return
	}

	host := hostOnly(req.Host)

	if req.Method == http.MethodConnect {
		if !isDomainAllowed(host, cfg) {
			fmt.Fprintf(os.Stderr, "%s blocked domain: %s\n", time.Now().Format(time.RFC3339), req.Host)
			fmt.Fprintf(conn, "HTTP/1.1 403 Forbidden\r\n\r\n")
			return
		}
		// MITM: intercept the TLS connection to inspect HTTP requests
		fmt.Fprintf(conn, "HTTP/1.1 200 Connection Established\r\n\r\n")
		handleMITM(conn, host, req.Host, cfg)
	} else {
		// Plaintext HTTP — apply full filtering
		if code, reason := applyFilters(req, host, cfg); code != 0 {
			fmt.Fprintf(os.Stderr, "%s blocked %s %s (%s, host: %s)\n",
				time.Now().Format(time.RFC3339), req.Method, req.URL, reason, req.Host)
			fmt.Fprintf(conn, "HTTP/1.1 %d %s\r\n\r\n", code, http.StatusText(code))
			return
		}
		if req.URL.Host == "" {
			req.URL.Host = req.Host
		}
		if req.URL.Scheme == "" {
			req.URL.Scheme = "http"
		}
		req.RequestURI = "" // Must be empty for RoundTrip
		resp, err := directTransport.RoundTrip(req)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s upstream error for %s: %v\n", time.Now().Format(time.RFC3339), req.URL, err)
			fmt.Fprintf(conn, "HTTP/1.1 502 Bad Gateway\r\n\r\n")
			return
		}
		defer resp.Body.Close()
		resp.Write(conn)
	}
}

func handleMITM(clientConn net.Conn, host, hostPort string, cfg Config) {
	// Mint a certificate for this host
	leafCert, err := mintCert(host)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s mint cert error for %s: %v\n", time.Now().Format(time.RFC3339), host, err)
		return
	}

	// TLS handshake with the client
	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{*leafCert},
	}
	clientTLS := tls.Server(clientConn, tlsConfig)
	if err := clientTLS.Handshake(); err != nil {
		fmt.Fprintf(os.Stderr, "%s client TLS handshake error for %s: %v\n", time.Now().Format(time.RFC3339), host, err)
		return
	}
	defer clientTLS.Close()

	// Connect to the real upstream server
	upstreamTLS, err := tls.Dial("tcp", hostPort, &tls.Config{
		ServerName: host,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s upstream dial error for %s: %v\n", time.Now().Format(time.RFC3339), hostPort, err)
		resp := &http.Response{
			StatusCode: http.StatusBadGateway,
			ProtoMajor: 1,
			ProtoMinor: 1,
			Header:     make(http.Header),
		}
		resp.Write(clientTLS)
		return
	}
	defer upstreamTLS.Close()
	upstreamBuf := bufio.NewReader(upstreamTLS)

	// Read and forward HTTP requests over the decrypted TLS stream
	clientBuf := bufio.NewReader(clientTLS)
	for {
		req, err := http.ReadRequest(clientBuf)
		if err != nil {
			return // Client closed or protocol error
		}

		// Apply filters to the decrypted request
		if code, reason := applyFilters(req, host, cfg); code != 0 {
			fmt.Fprintf(os.Stderr, "%s blocked %s https://%s%s (%s)\n",
				time.Now().Format(time.RFC3339), req.Method, host, req.URL.Path, reason)
			resp := &http.Response{
				StatusCode: code,
				Status:     fmt.Sprintf("%d %s", code, http.StatusText(code)),
				ProtoMajor: 1,
				ProtoMinor: 1,
				Header:     make(http.Header),
			}
			resp.Header.Set("Connection", "close")
			resp.Write(clientTLS)
			return
		}

		// Forward request directly to upstream (no http.Transport — we
		// manage the TLS conn ourselves to support keep-alive properly).
		req.URL.Scheme = ""
		req.URL.Host = ""
		// RequestURI must be the path for a direct (non-proxy) request
		req.RequestURI = req.URL.RequestURI()
		if err := req.Write(upstreamTLS); err != nil {
			fmt.Fprintf(os.Stderr, "%s upstream write error for %s: %v\n", time.Now().Format(time.RFC3339), host, err)
			return
		}
		resp, err := http.ReadResponse(upstreamBuf, req)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s upstream read error for %s: %v\n", time.Now().Format(time.RFC3339), host, err)
			return
		}
		resp.Write(clientTLS)
		resp.Body.Close()

		// If either side signals close, stop
		if resp.Close || req.Close {
			return
		}
	}
}
