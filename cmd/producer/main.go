package main

import (
	"flag"
	"fmt"
	"log"
	"time"

	"tiny/pkg/beanqueue"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:11300", "beanstalkd address")
	tube := flag.String("tube", "default", "beanstalkd tube name")
	payload := flag.String("payload", `{"type":"email","to":"user@example.com"}`, "job payload")
	priority := flag.Uint("priority", 1024, "job priority, lower is higher priority")
	delay := flag.Duration("delay", 0, "job delay before available")
	ttr := flag.Duration("ttr", 30*time.Second, "time-to-run for worker")
	flag.Parse()

	q, err := beanqueue.Dial(beanqueue.Config{Addr: *addr, Tube: *tube})
	if err != nil {
		log.Fatal(err)
	}
	defer q.Close()

	id, err := q.Enqueue([]byte(*payload), uint32(*priority), *delay, *ttr)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("enqueued job id=%d tube=%s\n", id, *tube)
}
