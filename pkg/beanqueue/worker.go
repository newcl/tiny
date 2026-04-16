package beanqueue

import (
	"context"
	"errors"
	"log"
	"time"
)

type Handler func(ctx context.Context, job Job) error

type WorkerConfig struct {
	ReserveTimeout time.Duration
	RetryDelay     time.Duration
	Priority       uint32
}

func (c WorkerConfig) withDefaults() WorkerConfig {
	if c.ReserveTimeout <= 0 {
		c.ReserveTimeout = 5 * time.Second
	}
	if c.RetryDelay < 0 {
		c.RetryDelay = 0
	}
	return c
}

func RunWorker(ctx context.Context, q Queue, handler Handler, cfg WorkerConfig) error {
	if handler == nil {
		return errors.New("handler cannot be nil")
	}
	cfg = cfg.withDefaults()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		job, err := q.Reserve(cfg.ReserveTimeout)
		if err != nil {
			if errors.Is(err, ErrTimeout) {
				continue
			}
			return err
		}

		if err := handler(ctx, job); err != nil {
			if releaseErr := q.Release(job.ID, cfg.Priority, cfg.RetryDelay); releaseErr != nil {
				log.Printf("release job %d failed after handler error: %v", job.ID, releaseErr)
			}
			continue
		}

		if err := q.Delete(job.ID); err != nil {
			log.Printf("delete job %d failed: %v", job.ID, err)
		}
	}
}
