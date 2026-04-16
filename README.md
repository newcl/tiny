# tiny

A tiny Go interface for working with beanstalkd queues.

## Features

- Enqueue jobs
- Reserve and process jobs
- Ack (`Delete`) and retry (`Release`)
- Bury and kick jobs
- Tube stats
- Worker loop helper with retry behavior

## Requirements

- Go 1.22+
- beanstalkd running (default: `127.0.0.1:11300`)

## Install deps

```bash
go mod tidy
```

## Producer example

```bash
go run ./cmd/producer \
  -addr 127.0.0.1:11300 \
  -tube emails \
  -payload '{"to":"user@example.com","template":"welcome"}'
```

## Worker example

```bash
go run ./cmd/worker \
  -addr 127.0.0.1:11300 \
  -tube emails
```

## REST API example

Run API server:

```bash
go run ./cmd/api \
  -listen :8080 \
  -beanstalk-addr 127.0.0.1:11300 \
  -tube jobs
```

Health check:

```bash
curl -sS http://127.0.0.1:8080/healthz
```

Submit a job to queue:

```bash
curl -sS -X POST "http://127.0.0.1:8080/jobs" \
  -H "Content-Type: application/json" \
  -d '{"type":"email","to":"user@example.com","subject":"Hello"}'
```

Submit with per-job options:

```bash
curl -sS -X POST "http://127.0.0.1:8080/jobs?priority=512&delay_seconds=2&ttr_seconds=60" \
  -H "Content-Type: application/json" \
  -d '{"type":"report","report_id":"rpt_123"}'
```

## Package usage

```go
q, err := beanqueue.Dial(beanqueue.Config{Addr: "127.0.0.1:11300", Tube: "emails"})
if err != nil {
    panic(err)
}
defer q.Close()

id, err := q.Enqueue([]byte(`{"task":"send_email"}`), 1024, 0, 30*time.Second)
if err != nil {
    panic(err)
}
_ = id
```

Main package path: `pkg/beanqueue`
