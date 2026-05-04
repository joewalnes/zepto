#!/usr/bin/env bash
# QA-SYN-009: Go syntax highlighting appearance
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-009: Go syntax highlighting (visual)"

file=$(qa_tmpfile_nl "syn009.go" 'package main

import (
	"fmt"
	"sync"
	"time"
)

// Server holds the application state
type Server struct {
	Port    int
	Name    string
	running bool
	mu      sync.Mutex
}

/* NewServer creates a server instance */
func NewServer(name string, port int) *Server {
	return &Server{
		Port:    port,
		Name:    name,
		running: false,
	}
}

func (s *Server) Start() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.running = true

	go func() {
		for i := 0; i < 10; i++ {
			time.Sleep(100 * time.Millisecond)
			fmt.Printf("tick %d\n", i)
		}
	}()

	ch := make(chan string, 5)
	ch <- "hello"
	return nil
}

func main() {
	srv := NewServer("api", 8080)
	if err := srv.Start(); err != nil {
		fmt.Println("Error:", err)
	}
}')
qa_start "$file"

shot="$QA_TMPDIR/go_syntax.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Go source file in a terminal text editor with syntax highlighting. Verify: (1) The code is NOT all one color — there are at least 3 distinct colors visible. (2) Keywords like 'func', 'return', 'if', 'for' appear in a color different from regular identifiers. (3) Strings in double quotes have their own color. (4) Comments (//) appear in a muted/gray color." \
    "Go syntax highlighting with multiple colors"

qa_keys "ctrl-q"

qa_summary
