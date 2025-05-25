;; Certification Verification Contract
;; Validates compliance claims and certifications

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u400))
(define-constant err-unauthorized (err u401))
(define-constant err-cert-not-found (err u402))
(define-constant err-cert-expired (err u403))
(define-constant err-invalid-issuer (err u404))

;; Certification types
(define-constant cert-type-organic u1)
(define-constant cert-type-fair-trade u2)
(define-constant cert-type-iso u3)
(define-constant cert-type-haccp u4)
(define-constant cert-type-gmp u5)

;; Data structures
(define-map certifications
  { cert-id: (string-ascii 50) }
  {
    cert-type: uint,
    name: (string-ascii 100),
    description: (string-ascii 500),
    issuer: principal,
    subject: principal,
    issued-at: uint,
    expires-at: uint,
    is-active: bool,
    verification-hash: (string-ascii 64)
  }
)

(define-map authorized-issuers
  { issuer: principal, cert-type: uint }
  {
    authorized-at: uint,
    authorized-by: principal,
    is-active: bool
  }
)

(define-map product-certifications
  { product-id: (string-ascii 50), cert-id: (string-ascii 50) }
  {
    applied-at: uint,
    applied-by: principal,
    verification-status: uint ;; 0=pending, 1=verified, 2=rejected
  }
)

;; Read-only functions
(define-read-only (get-certification (cert-id (string-ascii 50)))
  (map-get? certifications { cert-id: cert-id })
)

(define-read-only (is-certification-valid (cert-id (string-ascii 50)))
  (match (map-get? certifications { cert-id: cert-id })
    cert-data (and
      (get is-active cert-data)
      (> (get expires-at cert-data) block-height)
    )
    false
  )
)

(define-read-only (is-authorized-issuer (issuer principal) (cert-type uint))
  (match (map-get? authorized-issuers { issuer: issuer, cert-type: cert-type })
    issuer-data (get is-active issuer-data)
    false
  )
)

(define-read-only (get-product-certification (product-id (string-ascii 50)) (cert-id (string-ascii 50)))
  (map-get? product-certifications { product-id: product-id, cert-id: cert-id })
)

;; Public functions
(define-public (authorize-issuer (issuer principal) (cert-type uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)

    (map-set authorized-issuers
      { issuer: issuer, cert-type: cert-type }
      {
        authorized-at: block-height,
        authorized-by: tx-sender,
        is-active: true
      }
    )
    (ok true)
  )
)

(define-public (issue-certification
  (cert-id (string-ascii 50))
  (cert-type uint)
  (name (string-ascii 100))
  (description (string-ascii 500))
  (subject principal)
  (expires-at uint)
  (verification-hash (string-ascii 64))
)
  (begin
    ;; Check if caller is authorized issuer
    (asserts! (is-authorized-issuer tx-sender cert-type) err-invalid-issuer)

    ;; Issue certification
    (map-set certifications
      { cert-id: cert-id }
      {
        cert-type: cert-type,
        name: name,
        description: description,
        issuer: tx-sender,
        subject: subject,
        issued-at: block-height,
        expires-at: expires-at,
        is-active: true,
        verification-hash: verification-hash
      }
    )
    (ok true)
  )
)

(define-public (apply-certification-to-product (product-id (string-ascii 50)) (cert-id (string-ascii 50)))
  (begin
    ;; Check if certification exists and is valid
    (asserts! (is-certification-valid cert-id) err-cert-not-found)

    ;; Apply certification to product
    (map-set product-certifications
      { product-id: product-id, cert-id: cert-id }
      {
        applied-at: block-height,
        applied-by: tx-sender,
        verification-status: u0 ;; pending
      }
    )
    (ok true)
  )
)

(define-public (verify-product-certification (product-id (string-ascii 50)) (cert-id (string-ascii 50)) (status uint))
  (begin
    ;; Check if certification application exists
    (match (map-get? product-certifications { product-id: product-id, cert-id: cert-id })
      cert-app (begin
        ;; Check if caller is authorized (certification issuer or contract owner)
        (match (map-get? certifications { cert-id: cert-id })
          cert-data (begin
            (asserts! (or (is-eq tx-sender (get issuer cert-data)) (is-eq tx-sender contract-owner)) err-unauthorized)

            ;; Update verification status
            (map-set product-certifications
              { product-id: product-id, cert-id: cert-id }
              (merge cert-app { verification-status: status })
            )
            (ok true)
          )
          err-cert-not-found
        )
      )
      err-cert-not-found
    )
  )
)

(define-public (revoke-certification (cert-id (string-ascii 50)))
  (begin
    ;; Check if certification exists and caller is issuer
    (match (map-get? certifications { cert-id: cert-id })
      cert-data (begin
        (asserts! (is-eq tx-sender (get issuer cert-data)) err-unauthorized)

        ;; Revoke certification
        (map-set certifications
          { cert-id: cert-id }
          (merge cert-data { is-active: false })
        )
        (ok true)
      )
      err-cert-not-found
    )
  )
)
