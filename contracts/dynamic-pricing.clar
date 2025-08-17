;; Dynamic Pricing Contract
;; Implements demand-based pricing and route optimization

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-ROUTE (err u301))
(define-constant ERR-INVALID-MULTIPLIER (err u302))
(define-constant ERR-INVALID-TIME (err u303))

;; Time periods for pricing
(define-constant PEAK-MORNING-START u6)   ;; 6 AM
(define-constant PEAK-MORNING-END u9)     ;; 9 AM
(define-constant PEAK-EVENING-START u17)  ;; 5 PM
(define-constant PEAK-EVENING-END u19)    ;; 7 PM

;; Data structures
(define-map route-demand
  { route-id: uint, transport-mode: uint }
  {
    base-price: uint,
    current-multiplier: uint,
    peak-multiplier: uint,
    off-peak-multiplier: uint,
    demand-level: uint,
    last-updated: uint,
    total-passengers: uint,
    capacity: uint
  }
)

(define-map pricing-history
  { history-id: uint }
  {
    route-id: uint,
    transport-mode: uint,
    timestamp: uint,
    price: uint,
    demand-level: uint,
    passengers: uint
  }
)

(define-map surge-events
  { event-id: uint }
  {
    route-id: uint,
    transport-mode: uint,
    start-time: uint,
    end-time: uint,
    surge-multiplier: uint,
    reason: (string-ascii 100),
    active: bool
  }
)

;; Data variables
(define-data-var next-history-id uint u1)
(define-data-var next-event-id uint u1)
(define-data-var global-demand-factor uint u100) ;; Base 100%

;; Public functions

;; Initialize route pricing
(define-public (initialize-route-pricing (route-id uint) (transport-mode uint) (base-price uint) (capacity uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set route-demand
      { route-id: route-id, transport-mode: transport-mode }
      {
        base-price: base-price,
        current-multiplier: u100,
        peak-multiplier: u150,
        off-peak-multiplier: u80,
        demand-level: u50,
        last-updated: block-height,
        total-passengers: u0,
        capacity: capacity
      }
    )

    (ok true)
  )
)

;; Calculate current price for a route
(define-public (calculate-price (route-id uint) (transport-mode uint))
  (let (
    (route-info (unwrap! (map-get? route-demand { route-id: route-id, transport-mode: transport-mode }) ERR-INVALID-ROUTE))
    (current-hour (mod (/ block-height u144) u24)) ;; Approximate hour of day
    (base-price (get base-price route-info))
    (demand-level (get demand-level route-info))
    (time-multiplier (get-time-multiplier current-hour))
    (demand-multiplier (get-demand-multiplier demand-level))
    (surge-multiplier (get-active-surge-multiplier route-id transport-mode))
  )
    (let (
      (final-multiplier (/ (* (* time-multiplier demand-multiplier) surge-multiplier) u10000))
      (final-price (/ (* base-price final-multiplier) u100))
    )
      ;; Record pricing history
      (record-pricing-history route-id transport-mode final-price demand-level)
      (ok final-price)
    )
  )
)

;; Update demand level based on passenger count
(define-public (update-demand (route-id uint) (transport-mode uint) (passenger-count uint))
  (let (
    (route-info (unwrap! (map-get? route-demand { route-id: route-id, transport-mode: transport-mode }) ERR-INVALID-ROUTE))
    (capacity (get capacity route-info))
    (utilization (/ (* passenger-count u100) capacity))
    (new-demand-level (calculate-demand-level utilization))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set route-demand
      { route-id: route-id, transport-mode: transport-mode }
      (merge route-info {
        demand-level: new-demand-level,
        last-updated: block-height,
        total-passengers: (+ (get total-passengers route-info) passenger-count)
      })
    )

    (ok new-demand-level)
  )
)

;; Create surge pricing event
(define-public (create-surge-event (route-id uint) (transport-mode uint) (duration uint) (surge-multiplier uint) (reason (string-ascii 100)))
  (let (
    (event-id (var-get next-event-id))
    (current-time block-height)
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= surge-multiplier u100) (<= surge-multiplier u300)) ERR-INVALID-MULTIPLIER)

    (map-set surge-events
      { event-id: event-id }
      {
        route-id: route-id,
        transport-mode: transport-mode,
        start-time: current-time,
        end-time: (+ current-time duration),
        surge-multiplier: surge-multiplier,
        reason: reason,
        active: true
      }
    )

    (var-set next-event-id (+ event-id u1))
    (ok event-id)
  )
)

;; End surge pricing event
(define-public (end-surge-event (event-id uint))
  (let (
    (event-info (unwrap! (map-get? surge-events { event-id: event-id }) ERR-INVALID-ROUTE))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set surge-events
      { event-id: event-id }
      (merge event-info { active: false })
    )

    (ok true)
  )
)

;; Private functions

;; Record pricing history
(define-private (record-pricing-history (route-id uint) (transport-mode uint) (price uint) (demand-level uint))
  (let (
    (history-id (var-get next-history-id))
  )
    (map-set pricing-history
      { history-id: history-id }
      {
        route-id: route-id,
        transport-mode: transport-mode,
        timestamp: block-height,
        price: price,
        demand-level: demand-level,
        passengers: u0
      }
    )

    (var-set next-history-id (+ history-id u1))
    true
  )
)

;; Get time-based multiplier
(define-private (get-time-multiplier (hour uint))
  (if (or (and (>= hour PEAK-MORNING-START) (< hour PEAK-MORNING-END))
          (and (>= hour PEAK-EVENING-START) (< hour PEAK-EVENING-END)))
    u150  ;; Peak hours: 150%
    u80   ;; Off-peak hours: 80%
  )
)

;; Get demand-based multiplier
(define-private (get-demand-multiplier (demand-level uint))
  (if (>= demand-level u80)
    u200  ;; High demand: 200%
    (if (>= demand-level u60)
      u150  ;; Medium demand: 150%
      (if (>= demand-level u40)
        u100  ;; Normal demand: 100%
        u80   ;; Low demand: 80%
      )
    )
  )
)

;; Calculate demand level based on utilization
(define-private (calculate-demand-level (utilization uint))
  (if (>= utilization u90)
    u100  ;; Very high demand
    (if (>= utilization u70)
      u80   ;; High demand
      (if (>= utilization u50)
        u60   ;; Medium demand
        (if (>= utilization u30)
          u40   ;; Low demand
          u20   ;; Very low demand
        )
      )
    )
  )
)

;; Get active surge multiplier for route
(define-private (get-active-surge-multiplier (route-id uint) (transport-mode uint))
  (default-to u100
    (get surge-multiplier
      (map-get? surge-events { event-id: u1 }) ;; Simplified - would need iteration in real implementation
    )
  )
)

;; Read-only functions

;; Get route demand information
(define-read-only (get-route-demand (route-id uint) (transport-mode uint))
  (map-get? route-demand { route-id: route-id, transport-mode: transport-mode })
)

;; Get pricing history
(define-read-only (get-pricing-history (history-id uint))
  (map-get? pricing-history { history-id: history-id })
)

;; Get surge event
(define-read-only (get-surge-event (event-id uint))
  (map-get? surge-events { event-id: event-id })
)

;; Get current price estimate
(define-read-only (get-price-estimate (route-id uint) (transport-mode uint))
  (match (map-get? route-demand { route-id: route-id, transport-mode: transport-mode })
    route-info
    (let (
      (current-hour (mod (/ block-height u144) u24))
      (base-price (get base-price route-info))
      (demand-level (get demand-level route-info))
      (time-multiplier (get-time-multiplier current-hour))
      (demand-multiplier (get-demand-multiplier demand-level))
    )
      (some (/ (* base-price (* time-multiplier demand-multiplier)) u10000))
    )
    none
  )
)
