package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"tiny/pkg/beanqueue"
)

type apiServer struct {
	queue           beanqueue.Queue
	tube            string
	defaultPriority uint32
	defaultDelay    time.Duration
	defaultTTR      time.Duration
}

type enqueueResponse struct {
	JobID uint64 `json:"job_id"`
	Tube  string `json:"tube"`
}

type errorResponse struct {
	Error string `json:"error"`
}

func main() {
	listenAddr := flag.String("listen", ":8080", "HTTP listen address")
	beanstalkAddr := flag.String("beanstalk-addr", "127.0.0.1:11300", "beanstalkd address")
	tube := flag.String("tube", "jobs", "beanstalkd tube name")
	defaultPriority := flag.Uint("priority", 1024, "default job priority (lower is higher priority)")
	defaultDelay := flag.Duration("delay", 0, "default job delay")
	defaultTTR := flag.Duration("ttr", 30*time.Second, "default job time-to-run")
	flag.Parse()

	q, err := beanqueue.Dial(beanqueue.Config{Addr: *beanstalkAddr, Tube: *tube})
	if err != nil {
		log.Fatal(err)
	}
	defer q.Close()

	s := &apiServer{
		queue:           q,
		tube:            *tube,
		defaultPriority: uint32(*defaultPriority),
		defaultDelay:    *defaultDelay,
		defaultTTR:      *defaultTTR,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealthz)
	mux.HandleFunc("POST /jobs", s.handleEnqueue)

	httpServer := &http.Server{
		Addr:              *listenAddr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       30 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := httpServer.Shutdown(shutdownCtx); err != nil {
			log.Printf("http shutdown error: %v", err)
		}
	}()

	log.Printf("API listening on %s, queue=%s, beanstalk=%s", *listenAddr, *tube, *beanstalkAddr)
	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}

func (s *apiServer) handleHealthz(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *apiServer) handleEnqueue(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		writeError(w, http.StatusBadRequest, "failed to read body")
		return
	}
	defer r.Body.Close()

	if len(body) == 0 {
		writeError(w, http.StatusBadRequest, "request body is required")
		return
	}
	if !json.Valid(body) {
		writeError(w, http.StatusBadRequest, "body must be valid JSON")
		return
	}

	priority, delay, ttr, err := s.parseJobOptions(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	jobID, err := s.queue.Enqueue(body, priority, delay, ttr)
	if err != nil {
		writeError(w, http.StatusBadGateway, fmt.Sprintf("failed to enqueue job: %v", err))
		return
	}

	writeJSON(w, http.StatusCreated, enqueueResponse{JobID: jobID, Tube: s.tube})
}

func (s *apiServer) parseJobOptions(r *http.Request) (uint32, time.Duration, time.Duration, error) {
	q := r.URL.Query()

	priority := s.defaultPriority
	if raw := q.Get("priority"); raw != "" {
		v, err := strconv.ParseUint(raw, 10, 32)
		if err != nil {
			return 0, 0, 0, errors.New("invalid priority query param")
		}
		priority = uint32(v)
	}

	delay := s.defaultDelay
	if raw := q.Get("delay_seconds"); raw != "" {
		v, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || v < 0 {
			return 0, 0, 0, errors.New("invalid delay_seconds query param")
		}
		delay = time.Duration(v) * time.Second
	}

	ttr := s.defaultTTR
	if raw := q.Get("ttr_seconds"); raw != "" {
		v, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || v <= 0 {
			return 0, 0, 0, errors.New("invalid ttr_seconds query param")
		}
		ttr = time.Duration(v) * time.Second
	}

	return priority, delay, ttr, nil
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("write response error: %v", err)
	}
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, errorResponse{Error: message})
}
