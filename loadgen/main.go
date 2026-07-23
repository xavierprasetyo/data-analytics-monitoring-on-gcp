// Package main implements a load generator for the DA Monitoring & Alerting lab.
//
// It connects to a Cloud SQL PostgreSQL instance and periodically:
//   - Inserts new orders (~5 every cycle)
//   - Updates random order statuses (~5 every cycle)
//
// This generates CDC events for Datastream to capture.
package main

import (
	"database/sql"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"time"

	_ "github.com/lib/pq"
)

var (
	db       *sql.DB
	products = []string{
		"Laptop Pro 16", "Wireless Mouse", "USB-C Hub", "Mechanical Keyboard",
		"4K Monitor", "Webcam HD", "Noise-Cancel Headphones", "Portable SSD 1TB",
		"Tablet 11-inch", "Smartwatch Ultra",
	}
	statuses     = []string{"pending", "confirmed", "processing", "shipped", "delivered", "cancelled"}
	regions      = []string{"us-east", "us-west", "eu-west", "eu-central", "ap-south", "ap-northeast"}
	insertCount  int64
	updateCount  int64
	errorCount   int64
)

func main() {
	// Configuration from environment variables
	dbHost := getEnv("DB_HOST", "127.0.0.1")
	dbPort := getEnv("DB_PORT", "5432")
	dbUser := getEnv("DB_USER", "datastream_user")
	dbPass := getEnv("DB_PASS", "change-me")
	dbName := getEnv("DB_NAME", "source_db")
	intervalStr := getEnv("INTERVAL_SECONDS", "5")
	port := getEnv("PORT", "8080")

	interval, err := strconv.Atoi(intervalStr)
	if err != nil {
		log.Fatalf("Invalid INTERVAL_SECONDS: %v", err)
	}

	// Connect to PostgreSQL
	connStr := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		dbHost, dbPort, dbUser, dbPass, dbName,
	)

	log.Printf("Connecting to PostgreSQL at %s:%s/%s as %s...", dbHost, dbPort, dbName, dbUser)

	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatalf("Failed to open database connection: %v", err)
	}
	defer db.Close()

	db.SetMaxOpenConns(5)
	db.SetMaxIdleConns(2)
	db.SetConnMaxLifetime(5 * time.Minute)

	// Verify connectivity
	if err := db.Ping(); err != nil {
		log.Fatalf("Failed to ping database: %v", err)
	}
	log.Println("Connected to PostgreSQL successfully!")

	// Ensure table exists
	if err := ensureSchema(); err != nil {
		log.Fatalf("Failed to create schema: %v", err)
	}
	log.Println("Schema verified/created.")

	// Start the load generation loop
	go generateLoad(time.Duration(interval) * time.Second)

	// Health check HTTP server (required by Cloud Run)
	http.HandleFunc("/", healthHandler)
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/stats", statsHandler)

	log.Printf("Starting HTTP server on :%s (load interval: %ds)", port, interval)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("HTTP server failed: %v", err)
	}
}

func ensureSchema() error {
	schema := `
	CREATE TABLE IF NOT EXISTS orders (
		order_id     SERIAL PRIMARY KEY,
		customer_id  INTEGER NOT NULL,
		product      VARCHAR(100) NOT NULL,
		quantity     INTEGER NOT NULL DEFAULT 1,
		unit_price   NUMERIC(10, 2) NOT NULL,
		total_price  NUMERIC(10, 2) NOT NULL,
		status       VARCHAR(20) NOT NULL DEFAULT 'pending',
		region       VARCHAR(30) NOT NULL,
		created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);

	CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
	CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
	CREATE INDEX IF NOT EXISTS idx_orders_region ON orders(region);
	`
	_, err := db.Exec(schema)
	return err
}

func generateLoad(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for range ticker.C {
		// Insert new orders
		inserted := insertOrders(3 + rand.Intn(5)) // 3-7 orders per cycle
		insertCount += int64(inserted)

		// Update random order statuses
		updated := updateOrderStatuses(2 + rand.Intn(5)) // 2-6 updates per cycle
		updateCount += int64(updated)

		log.Printf("Cycle complete: inserted=%d, updated=%d (total: inserts=%d, updates=%d, errors=%d)",
			inserted, updated, insertCount, updateCount, errorCount)
	}
}

func insertOrders(count int) int {
	successful := 0
	for i := 0; i < count; i++ {
		product := products[rand.Intn(len(products))]
		customerID := 1000 + rand.Intn(9000)
		quantity := 1 + rand.Intn(5)
		unitPrice := 9.99 + float64(rand.Intn(99000))/100.0 // $9.99 - $999.99
		totalPrice := unitPrice * float64(quantity)
		region := regions[rand.Intn(len(regions))]

		_, err := db.Exec(`
			INSERT INTO orders (customer_id, product, quantity, unit_price, total_price, status, region)
			VALUES ($1, $2, $3, $4, $5, 'pending', $6)`,
			customerID, product, quantity, unitPrice, totalPrice, region,
		)
		if err != nil {
			log.Printf("ERROR inserting order: %v", err)
			errorCount++
			continue
		}
		successful++
	}
	return successful
}

func updateOrderStatuses(count int) int {
	successful := 0
	for i := 0; i < count; i++ {
		newStatus := statuses[1+rand.Intn(len(statuses)-1)] // skip "pending"

		result, err := db.Exec(`
			UPDATE orders
			SET status = $1, updated_at = NOW()
			WHERE order_id = (
				SELECT order_id FROM orders
				WHERE status != $1
				ORDER BY RANDOM()
				LIMIT 1
			)`, newStatus)
		if err != nil {
			log.Printf("ERROR updating order: %v", err)
			errorCount++
			continue
		}

		rows, _ := result.RowsAffected()
		if rows > 0 {
			successful++
		}
	}
	return successful
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	if err := db.Ping(); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprintf(w, `{"status":"unhealthy","error":"%s"}`, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"status":"healthy","inserts":%d,"updates":%d,"errors":%d}`,
		insertCount, updateCount, errorCount)
}

func statsHandler(w http.ResponseWriter, r *http.Request) {
	var orderCount int
	err := db.QueryRow("SELECT COUNT(*) FROM orders").Scan(&orderCount)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, `{"error":"%s"}`, err.Error())
		return
	}

	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"total_orders":%d,"inserts":%d,"updates":%d,"errors":%d}`,
		orderCount, insertCount, updateCount, errorCount)
}

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}
