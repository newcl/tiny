package main

import (
	"context"
	"encoding/json"
	"fmt"
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"tiny/pkg/beanqueue"
)

type jobEnvelope struct {
	Type string `json:"type"`
}

func main() {
	addr := flag.String("addr", "127.0.0.1:11300", "beanstalkd address")
	tube := flag.String("tube", "default", "beanstalkd tube name")
	retryDelay := flag.Duration("retry-delay", 10*time.Second, "delay before retry after handler failure")
	reserveTimeout := flag.Duration("reserve-timeout", 5*time.Second, "reserve wait timeout")
	flag.Parse()

	q, err := beanqueue.Dial(beanqueue.Config{Addr: *addr, Tube: *tube})
	if err != nil {
		log.Fatal(err)
	}
	defer q.Close()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	registry := map[string]beanqueue.Handler{
		"email": handleEmail,
		"report": handleReport,
	}
	handler := routeByType(registry)

	cfg := beanqueue.WorkerConfig{
		ReserveTimeout: *reserveTimeout,
		RetryDelay:     *retryDelay,
		Priority:       1024,
	}

	if err := beanqueue.RunWorker(ctx, q, handler, cfg); err != nil && err != context.Canceled {
		log.Fatal(err)
	}
}

func routeByType(registry map[string]beanqueue.Handler) beanqueue.Handler {
	return func(ctx context.Context, job beanqueue.Job) error {
		var payload jobEnvelope
		if err := json.Unmarshal(job.Body, &payload); err != nil {
			return fmt.Errorf("invalid job payload for id=%d: %w", job.ID, err)
		}
		if payload.Type == "" {
			return fmt.Errorf("missing job type for id=%d", job.ID)
		}

		h, ok := registry[payload.Type]
		if !ok {
			return fmt.Errorf("no handler registered for type=%q job_id=%d", payload.Type, job.ID)
		}
		return h(ctx, job)
	}
}

func handleEmail(_ context.Context, job beanqueue.Job) error {
	log.Printf("[email] processing job id=%d body=%s", job.ID, string(job.Body))
	return nil
}

func handleReport(_ context.Context, job beanqueue.Job) error {
	log.Printf("[report] processing job id=%d body=%s", job.ID, string(job.Body))
	return nil
}
