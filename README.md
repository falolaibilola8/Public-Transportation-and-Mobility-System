# Public Transportation and Mobility System

A comprehensive blockchain-based public transportation management system built with Clarity smart contracts. This system provides integrated ticketing, vehicle management, dynamic pricing, performance reporting, and accessibility support across multiple transport modes.

## System Overview

The system consists of five interconnected smart contracts:

### 1. Core Ticketing Contract (`ticketing.clar`)
- Manages integrated ticketing across buses, trains, trams, and other transport modes
- Handles ticket purchases, validations, and transfers
- Supports multi-modal journey planning and payment
- Tracks ticket usage and passenger flow

### 2. Vehicle Management Contract (`vehicle-management.clar`)
- Tracks vehicle maintenance schedules and records
- Manages safety inspection compliance
- Monitors vehicle availability and operational status
- Maintains fleet inventory and specifications

### 3. Dynamic Pricing Contract (`dynamic-pricing.clar`)
- Implements demand-based pricing algorithms
- Adjusts fares based on route popularity and time of day
- Provides surge pricing during peak hours
- Offers discounts for off-peak travel

### 4. Performance Reporting Contract (`performance-reporting.clar`)
- Tracks service performance metrics (on-time rates, delays, cancellations)
- Generates transparent public reports
- Monitors passenger satisfaction and feedback
- Provides data for service optimization

### 5. Accessibility Support Contract (`accessibility-support.clar`)
- Manages accessibility compliance requirements
- Coordinates passenger assistance programs
- Tracks wheelchair accessibility and special needs support
- Handles priority seating and assistance requests

## Key Features

- **Multi-Modal Integration**: Seamless ticketing across different transport types
- **Transparent Operations**: Public access to performance metrics and service data
- **Dynamic Pricing**: Fair, demand-based pricing that optimizes resource allocation
- **Safety First**: Comprehensive vehicle maintenance and inspection tracking
- **Inclusive Design**: Full accessibility support and assistance programs

## Smart Contract Architecture

All contracts are designed to work independently while sharing common data structures. The system uses Clarity's native data types and follows best practices for security and efficiency.

## Getting Started

1. Install Clarinet CLI
2. Run `clarinet check` to validate contracts
3. Use `npm test` to run the test suite
4. Deploy contracts using `clarinet deploy`

## Testing

The system includes comprehensive tests using Vitest to ensure all functionality works correctly across different scenarios and edge cases.
\`\`\`

```clar file="contracts/ticketing.clar"
;; Core Ticketing Contract
;; Manages integrated ticketing across multiple transport modes

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-TICKET (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-TICKET-EXPIRED (err u103))
(define-constant ERR-TICKET-ALREADY-USED (err u104))

;; Transport modes
(define-constant TRANSPORT-BUS u1)
(define-constant TRANSPORT-TRAIN u2)
(define-constant TRANSPORT-TRAM u3)
(define-constant TRANSPORT-METRO u4)

;; Data structures
(define-map tickets
  { ticket-id: uint }
  {
    owner: principal,
    transport-mode: uint,
    route-id: uint,
    purchase-time: uint,
    expiry-time: uint,
    price: uint,
    used: bool,
    transfer-count: uint
  }
)

(define-map user-balances
  { user: principal }
  { balance: uint }
)

(define-map routes
  { route-id: uint, transport-mode: uint }
  {
    name: (string-ascii 50),
    base-price: uint,
    active: bool,
    distance: uint
  }
)

;; Data variables
(define-data-var next-ticket-id uint u1)
(define-data-var next-route-id uint u1)

;; Public functions

;; Purchase a ticket
(define-public (purchase-ticket (transport-mode uint) (route-id uint))
  (let (
    (ticket-id (var-get next-ticket-id))
    (user tx-sender)
    (current-time block-height)
    (route-info (unwrap! (map-get? routes { route-id: route-id, transport-mode: transport-mode }) ERR-INVALID-TICKET))
    (ticket-price (get base-price route-info))
    (user-balance (default-to u0 (get balance (map-get? user-balances { user: user }))))
  )
    (asserts! (get active route-info) ERR-INVALID-TICKET)
    (asserts! (>= user-balance ticket-price) ERR-INSUFFICIENT-BALANCE)
    
    ;; Deduct balance
    (map-set user-balances 
      { user: user }
      { balance: (- user-balance ticket-price) }
    )
    
    ;; Create ticket
    (map-set tickets
      { ticket-id: ticket-id }
      {
        owner: user,
        transport-mode: transport-mode,
        route-id: route-id,
        purchase-time: current-time,
        expiry-time: (+ current-time u144), ;; 24 hours validity
        price: ticket-price,
        used: false,
        transfer-count: u0
      }
    )
    
    (var-set next-ticket-id (+ ticket-id u1))
    (ok ticket-id)
  )
)

;; Validate and use a ticket
(define-public (validate-ticket (ticket-id uint))
  (let (
    (ticket-info (unwrap! (map-get? tickets { ticket-id: ticket-id }) ERR-INVALID-TICKET))
    (current-time block-height)
  )
    (asserts! (is-eq (get owner ticket-info) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (get used ticket-info)) ERR-TICKET-ALREADY-USED)
    (asserts! (&lt;= current-time (get expiry-time ticket-info)) ERR-TICKET-EXPIRED)
    
    ;; Mark ticket as used
    (map-set tickets
      { ticket-id: ticket-id }
      (merge ticket-info { used: true })
    )
    
    (ok true)
  )
)

;; Add balance to user account
(define-public (add-balance (amount uint))
  (let (
    (user tx-sender)
    (current-balance (default-to u0 (get balance (map-get? user-balances { user: user }))))
  )
    (map-set user-balances
      { user: user }
      { balance: (+ current-balance amount) }
    )
    (ok (+ current-balance amount))
  )
)

;; Transfer ticket (for multi-modal journeys)
(define-public (transfer-ticket (ticket-id uint) (new-transport-mode uint) (new-route-id uint))
  (let (
    (ticket-info (unwrap! (map-get? tickets { ticket-id: ticket-id }) ERR-INVALID-TICKET))
    (current-time block-height)
    (transfer-count (get transfer-count ticket-info))
  )
    (asserts! (is-eq (get owner ticket-info) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (get used ticket-info)) ERR-TICKET-ALREADY-USED)
    (asserts! (&lt;= current-time (get expiry-time ticket-info)) ERR-TICKET-EXPIRED)
    (asserts! (&lt; transfer-count u3) ERR-INVALID-TICKET) ;; Max 3 transfers
    
    ;; Update ticket with new transport mode and route
    (map-set tickets
      { ticket-id: ticket-id }
      (merge ticket-info {
        transport-mode: new-transport-mode,
        route-id: new-route-id,
        transfer-count: (+ transfer-count u1)
      })
    )
    
    (ok true)
  )
)

;; Admin functions

;; Add a new route
(define-public (add-route (transport-mode uint) (name (string-ascii 50)) (base-price uint) (distance uint))
  (let (
    (route-id (var-get next-route-id))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (map-set routes
      { route-id: route-id, transport-mode: transport-mode }
      {
        name: name,
        base-price: base-price,
        active: true,
        distance: distance
      }
    )
    
    (var-set next-route-id (+ route-id u1))
    (ok route-id)
  )
)

;; Read-only functions

;; Get ticket information
(define-read-only (get-ticket (ticket-id uint))
  (map-get? tickets { ticket-id: ticket-id })
)

;; Get user balance
(define-read-only (get-balance (user principal))
  (default-to u0 (get balance (map-get? user-balances { user: user })))
)

;; Get route information
(define-read-only (get-route (route-id uint) (transport-mode uint))
  (map-get? routes { route-id: route-id, transport-mode: transport-mode })
)

;; Get next ticket ID
(define-read-only (get-next-ticket-id)
  (var-get next-ticket-id)
)
