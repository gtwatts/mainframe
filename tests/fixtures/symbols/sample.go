package main

import (
	"fmt"
	"net/http"
)

const MaxRetries = 3

var DefaultTimeout = 30

type Server struct {
	Host string
	Port int
}

type Handler interface {
	ServeHTTP(w http.ResponseWriter, r *http.Request)
	Shutdown() error
}

func NewServer(host string, port int) *Server {
	return &Server{Host: host, Port: port}
}

func (s *Server) Start() error {
	fmt.Printf("Starting on %s:%d\n", s.Host, s.Port)
	return nil
}

func (s *Server) Stop() error {
	return nil
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
}

func init() {
	fmt.Println("init")
}
