package beanqueue

import (
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/beanstalkd/go-beanstalk"
)

var ErrTimeout = beanstalk.ErrTimeout

type Config struct {
	Addr string
	Tube string
}

type Job struct {
	ID   uint64
	Body []byte
}

type Queue interface {
	Enqueue(body []byte, priority uint32, delay time.Duration, ttr time.Duration) (uint64, error)
	Reserve(timeout time.Duration) (Job, error)
	Delete(id uint64) error
	Release(id uint64, priority uint32, delay time.Duration) error
	Bury(id uint64, priority uint32) error
	Kick(bound uint64) (uint64, error)
	StatsTube() (map[string]string, error)
	Close() error
}

type Client struct {
	conn    *beanstalk.Conn
	tube    *beanstalk.Tube
	tubeSet *beanstalk.TubeSet
}

func Dial(cfg Config) (*Client, error) {
	if cfg.Addr == "" {
		cfg.Addr = "127.0.0.1:11300"
	}
	if cfg.Tube == "" {
		cfg.Tube = "default"
	}

	conn, err := beanstalk.Dial("tcp", cfg.Addr)
	if err != nil {
		return nil, err
	}

	return &Client{
		conn:    conn,
		tube:    &beanstalk.Tube{Conn: conn, Name: cfg.Tube},
		tubeSet: beanstalk.NewTubeSet(conn, cfg.Tube),
	}, nil
}

func (c *Client) Enqueue(body []byte, priority uint32, delay time.Duration, ttr time.Duration) (uint64, error) {
	if len(body) == 0 {
		return 0, errors.New("job body cannot be empty")
	}
	if ttr <= 0 {
		ttr = 30 * time.Second
	}
	return c.tube.Put(body, priority, delay, ttr)
}

func (c *Client) Reserve(timeout time.Duration) (Job, error) {
	id, body, err := c.tubeSet.Reserve(timeout)
	if err != nil {
		return Job{}, err
	}
	return Job{ID: id, Body: body}, nil
}

func (c *Client) Delete(id uint64) error {
	return c.conn.Delete(id)
}

func (c *Client) Release(id uint64, priority uint32, delay time.Duration) error {
	return c.conn.Release(id, priority, delay)
}

func (c *Client) Bury(id uint64, priority uint32) error {
	return c.conn.Bury(id, priority)
}

func (c *Client) Kick(bound uint64) (uint64, error) {
	if bound > uint64(math.MaxInt) {
		return 0, fmt.Errorf("kick bound exceeds max int: %d", bound)
	}
	kicked, err := c.conn.Kick(int(bound))
	if err != nil {
		return 0, err
	}
	return uint64(kicked), nil
}

func (c *Client) StatsTube() (map[string]string, error) {
	return c.tube.Stats()
}

func (c *Client) Close() error {
	return c.conn.Close()
}
