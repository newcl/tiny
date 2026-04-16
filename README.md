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
