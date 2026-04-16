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
  -tube jobs \
  -cors-origin http://127.0.0.1:5173
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

## Frontend (React) queue console

Run in a second terminal:

```bash
cd frontend
npm install
npm run dev
```

Open:

```text
http://127.0.0.1:5173
```

The UI posts JSON jobs to your API endpoint and lets you override priority, delay, and TTR.

Set API base URL for deployed frontend:

```bash
# local dev
VITE_API_BASE=http://127.0.0.1:8080 npm run dev

# build with explicit API base
VITE_API_BASE=https://your-api-domain npm run build
```

Cloudflare Pages:

- Add environment variable `VITE_API_BASE` in Pages project settings.
- Set it to your public HTTPS API URL.

If you see `Network error: Failed to fetch` when submitting:

- Your frontend is HTTPS but API URL is HTTP (mixed content blocked), or
- API is not publicly reachable, or
- API CORS origin does not include your frontend domain.

### Deploy frontend to Cloudflare Pages

Commands used:

```bash
cd frontend
npm install
npm run build
npx wrangler --version
npx wrangler pages project list
```

Create project once if missing:

```bash
npx wrangler pages project create tinyjobsui --production-branch main
```

Deploy current build:

```bash
npx wrangler pages deploy dist --project-name tinyjobsui --branch main
```

Deployed URLs:

- https://tinyjobsui.pages.dev
- Deployment preview URL is printed after each deploy command.

Custom domain note:

- Wrangler v4.83.0 does not support adding Pages custom domains via CLI.
- Add `tinyjobsui.elladali.com` in Cloudflare Dashboard: Pages -> tinyjobsui -> Custom domains.

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
