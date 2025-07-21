;; Decentralized Parking System Smart Contract
;; Description: A comprehensive parking system with spot management, reservations, payments, and dispute resolution

;; CONSTANTS AND ERROR CODES

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant PLATFORM-FEE-PERCENTAGE u5) ;; 5% platform fee
(define-constant MIN-PARKING-FEE u1000) ;; Minimum fee in microSTX
(define-constant MAX-PARKING-FEE u10000000) ;; Maximum fee in microSTX
(define-constant RESERVATION-TIMEOUT-BLOCKS u144) ;; ~24 hours at 10min blocks
(define-constant DISPUTE-WINDOW-BLOCKS u1008) ;; ~1 week for disputes
(define-constant MAX-SPOT-ID u999999) ;; Maximum spot ID
(define-constant MAX-RESERVATION-ID u999999) ;; Maximum reservation ID
(define-constant MAX-DISPUTE-ID u999999) ;; Maximum dispute ID

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-SPOT-NOT-FOUND (err u404))
(define-constant ERR-SPOT-ALREADY-EXISTS (err u409))
(define-constant ERR-SPOT-NOT-AVAILABLE (err u410))
(define-constant ERR-INVALID-AMOUNT (err u411))
(define-constant ERR-RESERVATION-EXPIRED (err u412))
(define-constant ERR-RESERVATION-NOT-FOUND (err u413))
(define-constant ERR-INVALID-TIME-RANGE (err u414))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u415))
(define-constant ERR-TRANSFER-FAILED (err u416))
(define-constant ERR-DISPUTE-WINDOW-CLOSED (err u417))
(define-constant ERR-INVALID-STATUS (err u418))
(define-constant ERR-ALREADY-RATED (err u419))
(define-constant ERR-INVALID-RATING (err u420))
(define-constant ERR-INVALID-INPUT (err u421))

;; DATA STRUCTURES

;; Parking spot status enumeration
(define-constant STATUS-AVAILABLE u0)
(define-constant STATUS-RESERVED u1)
(define-constant STATUS-OCCUPIED u2)
(define-constant STATUS-MAINTENANCE u3)

;; Reservation status enumeration
(define-constant RESERVATION-ACTIVE u0)
(define-constant RESERVATION-COMPLETED u1)
(define-constant RESERVATION-CANCELLED u2)
(define-constant RESERVATION-DISPUTED u3)

;; Parking spot data structure
(define-map parking-spots
  { spot-id: uint }
  {
    owner: principal,
    location: (string-ascii 100),
    hourly-rate: uint,
    status: uint,
    total-reservations: uint,
    total-earnings: uint,
    rating-sum: uint,
    rating-count: uint,
    created-at: uint,
    updated-at: uint
  }
)

;; Reservation data structure
(define-map reservations
  { reservation-id: uint }
  {
    spot-id: uint,
    renter: principal,
    start-time: uint,
    end-time: uint,
    total-cost: uint,
    platform-fee: uint,
    status: uint,
    created-at: uint,
    completed-at: (optional uint),
    dispute-reason: (optional (string-ascii 200))
  }
)

;; User profiles
(define-map user-profiles
  { user: principal }
  {
    total-spots-owned: uint,
    total-reservations: uint,
    reputation-score: uint,
    total-earned: uint,
    total-spent: uint,
    joined-at: uint
  }
)

;; User ratings for spots
(define-map user-ratings
  { renter: principal, spot-id: uint }
  { rating: uint, comment: (optional (string-ascii 200)) }
)

;; Dispute records
(define-map disputes
  { dispute-id: uint }
  {
    reservation-id: uint,
    complainant: principal,
    reason: (string-ascii 200),
    status: uint,
    resolution: (optional (string-ascii 200)),
    created-at: uint,
    resolved-at: (optional uint)
  }
)

;; VARIABLES

(define-data-var next-spot-id uint u1)
(define-data-var next-reservation-id uint u1)
(define-data-var next-dispute-id uint u1)
(define-data-var total-spots uint u0)
(define-data-var total-reservations uint u0)
(define-data-var platform-earnings uint u0)

;; INPUT VALIDATION FUNCTIONS

;; Validate spot ID
(define-private (is-valid-spot-id (spot-id uint))
  (and (> spot-id u0) (<= spot-id MAX-SPOT-ID))
)

;; Validate reservation ID
(define-private (is-valid-reservation-id (reservation-id uint))
  (and (> reservation-id u0) (<= reservation-id MAX-RESERVATION-ID))
)

;; Validate dispute ID
(define-private (is-valid-dispute-id (dispute-id uint))
  (and (> dispute-id u0) (<= dispute-id MAX-DISPUTE-ID))
)

;; Validate location string
(define-private (is-valid-location (location (string-ascii 100)))
  (> (len location) u0)
)

;; Validate rating
(define-private (is-valid-rating (rating uint))
  (and (>= rating u1) (<= rating u5))
)

;; Validate status
(define-private (is-valid-status (status uint))
  (<= status STATUS-MAINTENANCE)
)

;; Validate reason string
(define-private (is-valid-reason (reason (string-ascii 200)))
  (> (len reason) u0)
)

;; Validate comment string
(define-private (is-valid-comment (comment (optional (string-ascii 200))))
  (match comment
    some-comment (> (len some-comment) u0)
    true
  )
)

;; UTILITY FUNCTIONS

;; Calculate platform fee
(define-private (calculate-platform-fee (amount uint))
  (/ (* amount PLATFORM-FEE-PERCENTAGE) u100)
)

;; Get current block height
(define-private (get-current-time)
  block-height
)

;; Validate time range
(define-private (is-valid-time-range (start-time uint) (end-time uint))
  (and 
    (> end-time start-time)
    (>= start-time (get-current-time))
  )
)

;; Check if reservation is expired
(define-private (is-reservation-expired (reservation-id uint))
  (match (map-get? reservations { reservation-id: reservation-id })
    reservation
    (let ((current-time (get-current-time)))
      (and 
        (is-eq (get status reservation) RESERVATION-ACTIVE)
        (> current-time (+ (get end-time reservation) RESERVATION-TIMEOUT-BLOCKS))
      )
    )
    true
  )
)

;; PARKING SPOT MANAGEMENT

;; Register a new parking spot
(define-public (register-parking-spot 
  (location (string-ascii 100)) 
  (hourly-rate uint)
)
  (let (
    (spot-id (var-get next-spot-id))
    (current-time (get-current-time))
  )
    ;; Input validation
    (asserts! (is-valid-location location) ERR-INVALID-INPUT)
    (asserts! (and (>= hourly-rate MIN-PARKING-FEE) (<= hourly-rate MAX-PARKING-FEE)) ERR-INVALID-AMOUNT)
    
    ;; Create the parking spot
    (map-set parking-spots
      { spot-id: spot-id }
      {
        owner: tx-sender,
        location: location,
        hourly-rate: hourly-rate,
        status: STATUS-AVAILABLE,
        total-reservations: u0,
        total-earnings: u0,
        rating-sum: u0,
        rating-count: u0,
        created-at: current-time,
        updated-at: current-time
      }
    )
    
    ;; Update user profile
    (match (map-get? user-profiles { user: tx-sender })
      existing-profile
      (map-set user-profiles
        { user: tx-sender }
        (merge existing-profile { total-spots-owned: (+ (get total-spots-owned existing-profile) u1) })
      )
      ;; Create new profile
      (map-set user-profiles
        { user: tx-sender }
        {
          total-spots-owned: u1,
          total-reservations: u0,
          reputation-score: u100,
          total-earned: u0,
          total-spent: u0,
          joined-at: current-time
        }
      )
    )
    
    ;; Update counters
    (var-set next-spot-id (+ spot-id u1))
    (var-set total-spots (+ (var-get total-spots) u1))
    
    (ok spot-id)
  )
)

;; Update parking spot details
(define-public (update-parking-spot 
  (spot-id uint) 
  (location (optional (string-ascii 100)))
  (hourly-rate (optional uint))
)
  (begin
    ;; Input validation
    (asserts! (is-valid-spot-id spot-id) ERR-INVALID-INPUT)
    
    (match (map-get? parking-spots { spot-id: spot-id })
      spot
      (begin
        (asserts! (is-eq (get owner spot) tx-sender) ERR-NOT-AUTHORIZED)
        
        (let (
          (new-location (default-to (get location spot) location))
          (new-rate (default-to (get hourly-rate spot) hourly-rate))
        )
          ;; Validate new values
          (asserts! (is-valid-location new-location) ERR-INVALID-INPUT)
          (asserts! (and (>= new-rate MIN-PARKING-FEE) (<= new-rate MAX-PARKING-FEE)) ERR-INVALID-AMOUNT)
          
          (map-set parking-spots
            { spot-id: spot-id }
            (merge spot {
              location: new-location,
              hourly-rate: new-rate,
              updated-at: (get-current-time)
            })
          )
          (ok true)
        )
      )
      ERR-SPOT-NOT-FOUND
    )
  )
)

;; Set parking spot status
(define-public (set-spot-status (spot-id uint) (new-status uint))
  (begin
    ;; Input validation
    (asserts! (is-valid-spot-id spot-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-status new-status) ERR-INVALID-STATUS)
    
    (match (map-get? parking-spots { spot-id: spot-id })
      spot
      (begin
        (asserts! (is-eq (get owner spot) tx-sender) ERR-NOT-AUTHORIZED)
        
        (map-set parking-spots
          { spot-id: spot-id }
          (merge spot {
            status: new-status,
            updated-at: (get-current-time)
          })
        )
        (ok true)
      )
      ERR-SPOT-NOT-FOUND
    )
  )
)

;; RESERVATION MANAGEMENT

;; Make a reservation
(define-public (make-reservation 
  (spot-id uint) 
  (start-time uint) 
  (end-time uint)
)
  (let (
    (reservation-id (var-get next-reservation-id))
    (current-time (get-current-time))
  )
    ;; Input validation
    (asserts! (is-valid-spot-id spot-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-time-range start-time end-time) ERR-INVALID-TIME-RANGE)
    
    (match (map-get? parking-spots { spot-id: spot-id })
      spot
      (let (
        (duration-hours (/ (- end-time start-time) u6)) ;; Assuming 6 blocks per hour
        (total-cost (* (get hourly-rate spot) duration-hours))
        (platform-fee (calculate-platform-fee total-cost))
        (owner-payment (- total-cost platform-fee))
      )
        (asserts! (is-eq (get status spot) STATUS-AVAILABLE) ERR-SPOT-NOT-AVAILABLE)
        (asserts! (>= total-cost MIN-PARKING-FEE) ERR-INVALID-AMOUNT)
        
        ;; Transfer payment from renter
        (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
        
        ;; Create reservation
        (map-set reservations
          { reservation-id: reservation-id }
          {
            spot-id: spot-id,
            renter: tx-sender,
            start-time: start-time,
            end-time: end-time,
            total-cost: total-cost,
            platform-fee: platform-fee,
            status: RESERVATION-ACTIVE,
            created-at: current-time,
            completed-at: none,
            dispute-reason: none
          }
        )
        
        ;; Update spot status
        (map-set parking-spots
          { spot-id: spot-id }
          (merge spot {
            status: STATUS-RESERVED,
            total-reservations: (+ (get total-reservations spot) u1),
            updated-at: current-time
          })
        )
        
        ;; Update user profile
        (match (map-get? user-profiles { user: tx-sender })
          existing-profile
          (map-set user-profiles
            { user: tx-sender }
            (merge existing-profile { 
              total-reservations: (+ (get total-reservations existing-profile) u1),
              total-spent: (+ (get total-spent existing-profile) total-cost)
            })
          )
          ;; Create new profile
          (map-set user-profiles
            { user: tx-sender }
            {
              total-spots-owned: u0,
              total-reservations: u1,
              reputation-score: u100,
              total-earned: u0,
              total-spent: total-cost,
              joined-at: current-time
            }
          )
        )
        
        ;; Update counters
        (var-set next-reservation-id (+ reservation-id u1))
        (var-set total-reservations (+ (var-get total-reservations) u1))
        
        (ok reservation-id)
      )
      ERR-SPOT-NOT-FOUND
    )
  )
)

;; Complete a reservation
(define-public (complete-reservation (reservation-id uint))
  (begin
    ;; Input validation
    (asserts! (is-valid-reservation-id reservation-id) ERR-INVALID-INPUT)
    
    (match (map-get? reservations { reservation-id: reservation-id })
      reservation
      (match (map-get? parking-spots { spot-id: (get spot-id reservation) })
        spot
        (let (
          (current-time (get-current-time))
          (owner-payment (- (get total-cost reservation) (get platform-fee reservation)))
        )
          (asserts! 
            (or 
              (is-eq tx-sender (get renter reservation))
              (is-eq tx-sender (get owner spot))
            ) 
            ERR-NOT-AUTHORIZED
          )
          (asserts! (is-eq (get status reservation) RESERVATION-ACTIVE) ERR-INVALID-STATUS)
          (asserts! (>= current-time (get start-time reservation)) ERR-INVALID-TIME-RANGE)
          
          ;; Transfer payment to spot owner
          (try! (as-contract (stx-transfer? owner-payment tx-sender (get owner spot))))
          
          ;; Update platform earnings
          (var-set platform-earnings (+ (var-get platform-earnings) (get platform-fee reservation)))
          
          ;; Update reservation
          (map-set reservations
            { reservation-id: reservation-id }
            (merge reservation {
              status: RESERVATION-COMPLETED,
              completed-at: (some current-time)
            })
          )
          
          ;; Update spot
          (map-set parking-spots
            { spot-id: (get spot-id reservation) }
            (merge spot {
              status: STATUS-AVAILABLE,
              total-earnings: (+ (get total-earnings spot) owner-payment),
              updated-at: current-time
            })
          )
          
          ;; Update owner profile
          (match (map-get? user-profiles { user: (get owner spot) })
            owner-profile
            (map-set user-profiles
              { user: (get owner spot) }
              (merge owner-profile {
                total-earned: (+ (get total-earned owner-profile) owner-payment)
              })
            )
            false ;; Should not happen if spot exists
          )
          
          (ok true)
        )
        ERR-SPOT-NOT-FOUND
      )
      ERR-RESERVATION-NOT-FOUND
    )
  )
)

;; Cancel a reservation
(define-public (cancel-reservation (reservation-id uint))
  (begin
    ;; Input validation
    (asserts! (is-valid-reservation-id reservation-id) ERR-INVALID-INPUT)
    
    (match (map-get? reservations { reservation-id: reservation-id })
      reservation
      (match (map-get? parking-spots { spot-id: (get spot-id reservation) })
        spot
        (let ((current-time (get-current-time)))
          (asserts! (is-eq tx-sender (get renter reservation)) ERR-NOT-AUTHORIZED)
          (asserts! (is-eq (get status reservation) RESERVATION-ACTIVE) ERR-INVALID-STATUS)
          (asserts! (< current-time (get start-time reservation)) ERR-INVALID-TIME-RANGE)
          
          ;; Refund payment (minus a small cancellation fee)
          (let ((refund-amount (- (get total-cost reservation) (calculate-platform-fee (get total-cost reservation)))))
            (try! (as-contract (stx-transfer? refund-amount tx-sender (get renter reservation))))
          )
          
          ;; Update reservation
          (map-set reservations
            { reservation-id: reservation-id }
            (merge reservation { status: RESERVATION-CANCELLED })
          )
          
          ;; Update spot status back to available
          (map-set parking-spots
            { spot-id: (get spot-id reservation) }
            (merge spot {
              status: STATUS-AVAILABLE,
              updated-at: current-time
            })
          )
          
          (ok true)
        )
        ERR-SPOT-NOT-FOUND
      )
      ERR-RESERVATION-NOT-FOUND
    )
  )
)

;; RATING SYSTEM

;; Rate a parking spot after using it
(define-public (rate-parking-spot 
  (spot-id uint) 
  (rating uint) 
  (comment (optional (string-ascii 200)))
)
  (begin
    ;; Input validation
    (asserts! (is-valid-spot-id spot-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-rating rating) ERR-INVALID-RATING)
    (asserts! (is-valid-comment comment) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? user-ratings { renter: tx-sender, spot-id: spot-id })) ERR-ALREADY-RATED)
    
    ;; Verify user has completed a reservation for this spot
    
    (match (map-get? parking-spots { spot-id: spot-id })
      spot
      (begin
        ;; Store the rating
        (map-set user-ratings
          { renter: tx-sender, spot-id: spot-id }
          { rating: rating, comment: comment }
        )
        
        ;; Update spot rating
        (let (
          (new-rating-sum (+ (get rating-sum spot) rating))
          (new-rating-count (+ (get rating-count spot) u1))
        )
          (map-set parking-spots
            { spot-id: spot-id }
            (merge spot {
              rating-sum: new-rating-sum,
              rating-count: new-rating-count,
              updated-at: (get-current-time)
            })
          )
        )
        
        (ok true)
      )
      ERR-SPOT-NOT-FOUND
    )
  )
)

;; DISPUTE MANAGEMENT

;; File a dispute
(define-public (file-dispute 
  (reservation-id uint) 
  (reason (string-ascii 200))
)
  (begin
    ;; Input validation
    (asserts! (is-valid-reservation-id reservation-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-reason reason) ERR-INVALID-INPUT)
    
    (match (map-get? reservations { reservation-id: reservation-id })
      reservation
      (let (
        (dispute-id (var-get next-dispute-id))
        (current-time (get-current-time))
      )
        (asserts! (is-eq tx-sender (get renter reservation)) ERR-NOT-AUTHORIZED)
        (asserts! 
          (< current-time (+ (get end-time reservation) DISPUTE-WINDOW-BLOCKS))
          ERR-DISPUTE-WINDOW-CLOSED
        )
        
        ;; Create dispute record
        (map-set disputes
          { dispute-id: dispute-id }
          {
            reservation-id: reservation-id,
            complainant: tx-sender,
            reason: reason,
            status: u0, ;; Open
            resolution: none,
            created-at: current-time,
            resolved-at: none
          }
        )
        
        ;; Update reservation status
        (map-set reservations
          { reservation-id: reservation-id }
          (merge reservation {
            status: RESERVATION-DISPUTED,
            dispute-reason: (some reason)
          })
        )
        
        (var-set next-dispute-id (+ dispute-id u1))
        (ok dispute-id)
      )
      ERR-RESERVATION-NOT-FOUND
    )
  )
)

;; READ-ONLY FUNCTIONS

;; Get parking spot details
(define-read-only (get-parking-spot (spot-id uint))
  (map-get? parking-spots { spot-id: spot-id })
)

;; Get reservation details
(define-read-only (get-reservation (reservation-id uint))
  (map-get? reservations { reservation-id: reservation-id })
)

;; Get user profile
(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles { user: user })
)

;; Get spot rating
(define-read-only (get-spot-rating (spot-id uint))
  (match (map-get? parking-spots { spot-id: spot-id })
    spot
    (if (> (get rating-count spot) u0)
      (some (/ (get rating-sum spot) (get rating-count spot)))
      none
    )
    none
  )
)

;; Get available spots
(define-read-only (get-available-spots-count)
  (var-get total-spots) ;; Simplified - would need to filter by status
)

;; Get platform statistics
(define-read-only (get-platform-stats)
  {
    total-spots: (var-get total-spots),
    total-reservations: (var-get total-reservations),
    platform-earnings: (var-get platform-earnings)
  }
)

;; Check if user can rate a spot
(define-read-only (can-rate-spot (user principal) (spot-id uint))
  (is-none (map-get? user-ratings { renter: user, spot-id: spot-id }))
)

;; ADMIN FUNCTIONS

;; Withdraw platform earnings (only contract owner)
(define-public (withdraw-platform-earnings (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= amount (var-get platform-earnings)) ERR-INSUFFICIENT-PAYMENT)
    
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT-OWNER)))
    (var-set platform-earnings (- (var-get platform-earnings) amount))
    (ok true)
  )
)

;; Emergency functions for contract maintenance
(define-public (emergency-resolve-dispute 
  (dispute-id uint) 
  (resolution (string-ascii 200))
)
  (begin
    ;; Input validation
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-dispute-id dispute-id) ERR-INVALID-INPUT)
    (asserts! (> (len resolution) u0) ERR-INVALID-INPUT)
    
    (match (map-get? disputes { dispute-id: dispute-id })
      dispute
      (begin
        (map-set disputes
          { dispute-id: dispute-id }
          (merge dispute {
            status: u1, ;; Resolved
            resolution: (some resolution),
            resolved-at: (some (get-current-time))
          })
        )
        (ok true)
      )
      (err u404)
    )
  )
)