;; Publishing Coordination Contract
;; Coordinates document publishing workflows

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-PUBLICATION-NOT-FOUND (err u501))
(define-constant ERR-DOCUMENT-NOT-FOUND (err u502))
(define-constant ERR-INVALID-INPUT (err u503))
(define-constant ERR-ALREADY-PUBLISHED (err u504))
(define-constant ERR-INSUFFICIENT-REVIEWS (err u505))
(define-constant ERR-PUBLICATION-LOCKED (err u506))

;; Data Variables
(define-data-var next-publication-id uint u1)

;; Data Maps
(define-map publications
  { publication-id: uint }
  {
    document-id: uint,
    document-version: uint,
    publisher: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    content-hash: (string-ascii 64),
    status: (string-ascii 20),
    created-at: uint,
    published-at: (optional uint),
    is-public: bool,
    access-level: (string-ascii 20),
    download-count: uint,
    view-count: uint
  }
)

(define-map document-publications
  { document-id: uint, publication-id: uint }
  { is-active: bool }
)

(define-map publication-metadata
  { publication-id: uint }
  {
    tags: (list 10 (string-ascii 50)),
    category: (string-ascii 50),
    license: (string-ascii 100),
    doi: (optional (string-ascii 100)),
    isbn: (optional (string-ascii 20))
  }
)

(define-map publication-access
  { publication-id: uint, user: principal }
  {
    granted-at: uint,
    access-type: (string-ascii 20),
    expires-at: (optional uint)
  }
)

(define-map publisher-stats
  { publisher: principal }
  {
    total-publications: uint,
    public-publications: uint,
    total-downloads: uint,
    total-views: uint,
    last-published: uint
  }
)

;; Public Functions

;; Create a publication draft
(define-public (create-publication (document-id uint) (document-version uint) (title (string-ascii 100)) (description (string-ascii 500)) (content-hash (string-ascii 64)))
  (let
    (
      (publication-id (var-get next-publication-id))
      (caller tx-sender)
    )
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> (len content-hash) u0) ERR-INVALID-INPUT)
    (asserts! (<= (len description) u500) ERR-INVALID-INPUT)

    (map-set publications
      { publication-id: publication-id }
      {
        document-id: document-id,
        document-version: document-version,
        publisher: caller,
        title: title,
        description: description,
        content-hash: content-hash,
        status: "draft",
        created-at: block-height,
        published-at: none,
        is-public: false,
        access-level: "private",
        download-count: u0,
        view-count: u0
      }
    )

    (map-set document-publications
      { document-id: document-id, publication-id: publication-id }
      { is-active: true }
    )

    (var-set next-publication-id (+ publication-id u1))
    (ok publication-id)
  )
)

;; Publish a document
(define-public (publish-document (publication-id uint) (is-public bool) (access-level (string-ascii 20)))
  (let
    (
      (publication-data (unwrap! (map-get? publications { publication-id: publication-id }) ERR-PUBLICATION-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get publisher publication-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status publication-data) "draft") ERR-ALREADY-PUBLISHED)
    (asserts! (or (is-eq access-level "public") (is-eq access-level "private") (is-eq access-level "restricted")) ERR-INVALID-INPUT)

    (map-set publications
      { publication-id: publication-id }
      (merge publication-data {
        status: "published",
        published-at: (some block-height),
        is-public: is-public,
        access-level: access-level
      })
    )

    ;; Update publisher stats
    (let
      (
        (current-stats (default-to
          { total-publications: u0, public-publications: u0, total-downloads: u0, total-views: u0, last-published: u0 }
          (map-get? publisher-stats { publisher: tx-sender })
        ))
        (new-public-count (if is-public (+ (get public-publications current-stats) u1) (get public-publications current-stats)))
      )
      (map-set publisher-stats
        { publisher: tx-sender }
        {
          total-publications: (+ (get total-publications current-stats) u1),
          public-publications: new-public-count,
          total-downloads: (get total-downloads current-stats),
          total-views: (get total-views current-stats),
          last-published: block-height
        }
      )
    )

    (ok true)
  )
)

;; Set publication metadata
(define-public (set-publication-metadata (publication-id uint) (tags (list 10 (string-ascii 50))) (category (string-ascii 50)) (license (string-ascii 100)) (doi (optional (string-ascii 100))) (isbn (optional (string-ascii 20))))
  (let
    (
      (publication-data (unwrap! (map-get? publications { publication-id: publication-id }) ERR-PUBLICATION-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get publisher publication-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len category) u0) ERR-INVALID-INPUT)
    (asserts! (> (len license) u0) ERR-INVALID-INPUT)

    (map-set publication-metadata
      { publication-id: publication-id }
      {
        tags: tags,
        category: category,
        license: license,
        doi: doi,
        isbn: isbn
      }
    )
    (ok true)
  )
)

;; Grant access to a publication
(define-public (grant-publication-access (publication-id uint) (user principal) (access-type (string-ascii 20)) (expires-at (optional uint)))
  (let
    (
      (publication-data (unwrap! (map-get? publications { publication-id: publication-id }) ERR-PUBLICATION-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get publisher publication-data)) ERR-NOT-AUTHORIZED)
    (asserts! (or (is-eq access-type "read") (is-eq access-type "download") (is-eq access-type "full")) ERR-INVALID-INPUT)

    (map-set publication-access
      { publication-id: publication-id, user: user }
      {
        granted-at: block-height,
        access-type: access-type,
        expires-at: expires-at
      }
    )
    (ok true)
  )
)

;; Record publication view
(define-public (record-view (publication-id uint))
  (let
    (
      (publication-data (unwrap! (map-get? publications { publication-id: publication-id }) ERR-PUBLICATION-NOT-FOUND))
    )
    ;; Check if publication is accessible
    (asserts! (or (get is-public publication-data) (has-access publication-id tx-sender)) ERR-NOT-AUTHORIZED)

    (map-set publications
      { publication-id: publication-id }
      (merge publication-data { view-count: (+ (get view-count publication-data) u1) })
    )
    (ok true)
  )
)

;; Record publication download
(define-public (record-download (publication-id uint))
  (let
    (
      (publication-data (unwrap! (map-get? publications { publication-id: publication-id }) ERR-PUBLICATION-NOT-FOUND))
    )
    ;; Check if publication is accessible and user has download permission
    (asserts! (or (get is-public publication-data) (has-download-access publication-id tx-sender)) ERR-NOT-AUTHORIZED)

    (map-set publications
      { publication-id: publication-id }
      (merge publication-data { download-count: (+ (get download-count publication-data) u1) })
    )

    ;; Update publisher stats
    (let
      (
        (current-stats (default-to
          { total-publications: u0, public-publications: u0, total-downloads: u0, total-views: u0, last-published: u0 }
          (map-get? publisher-stats { publisher: (get publisher publication-data) })
        ))
      )
      (map-set publisher-stats
        { publisher: (get publisher publication-data) }
        (merge current-stats { total-downloads: (+ (get total-downloads current-stats) u1) })
      )
    )

    (ok true)
  )
)

;; Unpublish a document
(define-public (unpublish-document (publication-id uint))
  (let
    (
      (publication-data (unwrap! (map-get? publications { publication-id: publication-id }) ERR-PUBLICATION-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get publisher publication-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status publication-data) "published") ERR-INVALID-INPUT)

    (map-set publications
      { publication-id: publication-id }
      (merge publication-data {
        status: "unpublished",
        is-public: false,
        access-level: "private"
      })
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get publication information
(define-read-only (get-publication (publication-id uint))
  (map-get? publications { publication-id: publication-id })
)

;; Get publication metadata
(define-read-only (get-publication-metadata (publication-id uint))
  (map-get? publication-metadata { publication-id: publication-id })
)

;; Get publisher statistics
(define-read-only (get-publisher-stats (publisher principal))
  (default-to
    { total-publications: u0, public-publications: u0, total-downloads: u0, total-views: u0, last-published: u0 }
    (map-get? publisher-stats { publisher: publisher })
  )
)

;; Check if user has access to publication
(define-read-only (has-access (publication-id uint) (user principal))
  (match (map-get? publications { publication-id: publication-id })
    publication-data (or
      (get is-public publication-data)
      (is-eq user (get publisher publication-data))
      (is-some (map-get? publication-access { publication-id: publication-id, user: user }))
    )
    false
  )
)

;; Check if user has download access
(define-read-only (has-download-access (publication-id uint) (user principal))
  (match (map-get? publication-access { publication-id: publication-id, user: user })
    access-data (or
      (is-eq (get access-type access-data) "download")
      (is-eq (get access-type access-data) "full")
    )
    (has-access publication-id user)
  )
)

;; Get next publication ID
(define-read-only (get-next-publication-id)
  (var-get next-publication-id)
)

;; Check if publication is published
(define-read-only (is-published (publication-id uint))
  (match (map-get? publications { publication-id: publication-id })
    publication-data (is-eq (get status publication-data) "published")
    false
  )
)

;; Get publication access info
(define-read-only (get-publication-access (publication-id uint) (user principal))
  (map-get? publication-access { publication-id: publication-id, user: user })
)
