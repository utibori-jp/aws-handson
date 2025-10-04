package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
)

func getDBConnectionString() string {
	user := os.Getenv("DB_USER")
	password := os.Getenv("DB_PASS")
	host := os.Getenv("DB_HOST")
	dbname := os.Getenv("DB_NAME")
	sslmode := "require"

	connStr := fmt.Sprintf("host=%s user=%s password=%s dbname=%s sslmode=%s",
		host, user, password, dbname, sslmode)

	return connStr
}

// RDSに現在の時刻を記録するハンドラ
func recordTimeHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Invalid request method", http.StatusMethodNotAllowed)
		return
	}

	connStr := getDBConnectionString()
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		http.Error(w, "Failed to connect to database: "+err.Error(), http.StatusInternalServerError)
		log.Printf("Failed to connect to database: %v", err)
		return
	}
	defer db.Close()

	// タイムスタンプを挿入
	insertStmt := `INSERT INTO timestamps(recorded_at) VALUES($1)`
	_, err = db.Exec(insertStmt, time.Now())
	if err != nil {
		http.Error(w, "Failed to insert record: "+err.Error(), http.StatusInternalServerError)
		log.Printf("Failed to insert record: %v", err)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte("Record successful"))
	log.Println("Record successful")
}

// ルートパス("/")へのリクエストを処理し、HTMLファイルを返す
func rootHandler(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, "index.html")
}

func main() {
	// サーバーを起動
	http.HandleFunc("/", rootHandler)
	http.HandleFunc("/record-time", recordTimeHandler)

	port := "8080"
	log.Printf("Server starting on port %s...", port)

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}
