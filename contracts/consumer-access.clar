;; Consumer Access Contract
;; Enables product history queries and consumer interactions

(define-constant err-product-not-found (err u500))
(define-constant err-unauthorized-access (err u501))
(define-constant err-invalid-query (err u502))

;; Data structures for consumer queries
(define-map consumer-queries
  { query-id: (string-ascii 50) }
  {
    consumer: principal,
    product-id: (string-ascii 50),
    query-type: uint, ;; 1=full-history, 2=certifications, 3=origin, 4=current-location
    timestamp: uint,
    response-hash: (optional (string-ascii 64))
  }
)

(define-map product-access-permissions
  { product-id: (string-ascii 50) }
  {
    is-public: bool,
    authorized-viewers: (list 10 principal),
    access-level: uint ;; 1=basic, 2=detailed, 3=full
  }
)

(define-map consumer-ratings
  { product-id: (string-ascii 50), consumer: principal }
  {
    rating: uint, ;; 1-5 stars
    review: (string-ascii 500),
    verified-purchase: bool,
    timestamp: uint
  }
)

;; Read-only functions
(define-read-only (get-product-basic-info (product-id (string-ascii 50)))
  (let (
    (access-perms (default-to
      { is-public: true, authorized-viewers: (list), access-level: u1 }
      (map-get? product-access-permissions { product-id: product-id })
    ))
  )
    (if (get is-public access-perms)
      ;; Return basic product information (this would integrate with product-registration contract)
      (some {
        product-id: product-id,
        access-level: (get access-level access-perms),
        query-timestamp: block-height
      })
      none
    )
  )
)

(define-read-only (can-access-product (product-id (string-ascii 50)) (consumer principal))
  (match (map-get? product-access-permissions { product-id: product-id })
    access-perms (or
      (get is-public access-perms)
      (is-some (index-of (get authorized-viewers access-perms) consumer))
    )
    true ;; Default to public access if no permissions set
  )
)

(define-read-only (get-consumer-query (query-id (string-ascii 50)))
  (map-get? consumer-queries { query-id: query-id })
)

(define-read-only (get-product-rating (product-id (string-ascii 50)) (consumer principal))
  (map-get? consumer-ratings { product-id: product-id, consumer: consumer })
)

;; Public functions
(define-public (query-product-history (query-id (string-ascii 50)) (product-id (string-ascii 50)) (query-type uint))
  (begin
    ;; Check access permissions
    (asserts! (can-access-product product-id tx-sender) err-unauthorized-access)
    (asserts! (and (>= query-type u1) (<= query-type u4)) err-invalid-query)

    ;; Log the query
    (map-set consumer-queries
      { query-id: query-id }
      {
        consumer: tx-sender,
        product-id: product-id,
        query-type: query-type,
        timestamp: block-height,
        response-hash: none
      }
    )

    ;; Return success (actual data would be provided off-chain or through additional read functions)
    (ok {
      query-id: query-id,
      product-id: product-id,
      access-granted: true,
      timestamp: block-height
    })
  )
)

(define-public (set-product-access-permissions
  (product-id (string-ascii 50))
  (is-public bool)
  (authorized-viewers (list 10 principal))
  (access-level uint)
)
  (begin
    ;; Note: In a full implementation, this would check if caller is product owner
    ;; For simplicity, allowing any caller to set permissions

    (map-set product-access-permissions
      { product-id: product-id }
      {
        is-public: is-public,
        authorized-viewers: authorized-viewers,
        access-level: access-level
      }
    )
    (ok true)
  )
)

(define-public (rate-product
  (product-id (string-ascii 50))
  (rating uint)
  (review (string-ascii 500))
  (verified-purchase bool)
)
  (begin
    ;; Validate rating
    (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-query)

    ;; Add rating
    (map-set consumer-ratings
      { product-id: product-id, consumer: tx-sender }
      {
        rating: rating,
        review: review,
        verified-purchase: verified-purchase,
        timestamp: block-height
      }
    )
    (ok true)
  )
)

(define-public (update-query-response (query-id (string-ascii 50)) (response-hash (string-ascii 64)))
  (begin
    ;; Check if query exists and caller made the query
    (match (map-get? consumer-queries { query-id: query-id })
      query-data (begin
        (asserts! (is-eq tx-sender (get consumer query-data)) err-unauthorized-access)

        ;; Update response hash
        (map-set consumer-queries
          { query-id: query-id }
          (merge query-data { response-hash: (some response-hash) })
        )
        (ok true)
      )
      err-invalid-query
    )
  )
)

;; Utility function to get comprehensive product information
(define-read-only (get-product-summary (product-id (string-ascii 50)))
  (if (can-access-product product-id tx-sender)
    (some {
      product-id: product-id,
      access-level: (match (map-get? product-access-permissions { product-id: product-id })
        perms (get access-level perms)
        u1
      ),
      query-timestamp: block-height,
      public-access: (match (map-get? product-access-permissions { product-id: product-id })
        perms (get is-public perms)
        true
      )
    })
    none
  )
)
