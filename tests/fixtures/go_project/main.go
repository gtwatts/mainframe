package main

import (
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/lib/pq"
)

import "os"

type User struct {
	ID   int
	Name string
}

type UserService interface {
	GetUser(id int) (*User, error)
	CreateUser(name string) (*User, error)
}

type Repository interface {
	Find(id int) (*User, error)
}

func main() {
	r := gin.Default()
	r.GET("/health", healthCheck)
	r.Run(":8080")
}

func healthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func (s *service) GetUser(id int) (*User, error) {
	return s.repo.Find(id)
}

func helper() string {
	return fmt.Sprintf("version: %s", os.Getenv("VERSION"))
}
