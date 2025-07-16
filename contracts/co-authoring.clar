;; Co-authoring Coordination Contract
;; Coordinates document co-authoring between multiple authors

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-DOCUMENT-NOT-FOUND (err u201))
(define-constant ERR-AUTHOR-NOT-FOUND (err u202))
(define-constant ERR-ALREADY-AUTHOR (err u203))
(define-constant ERR-INVALID-INPUT (err u204))
(define-constant ERR-DOCUMENT-LOCKED (err u205))

;; Data Variables
(define-data-var next-document-id uint u1)

;; Data Maps
(define-map documents
  { document-id: uint }
  {
    title: (string-ascii 100),
    primary-author: principal,
    created-at: uint,
    last-modified: uint,
    is-locked: bool,
    total-authors: uint,
    version: uint
  }
)

(define-map document-authors
  { document-id: uint, author: principal }
  {
    added-at: uint,
    contribution-weight: uint,
    can-edit: bool,
    can-invite: bool,
    last-activity: uint
  }
)

(define-map author-documents
  { author: principal, document-id: uint }
  { is-active: bool }
)

(define-map document-versions
  { document-id: uint, version: uint }
  {
    content-hash: (string-ascii 64),
    author: principal,
    timestamp: uint,
    description: (string-ascii 200)
  }
)

;; Public Functions

;; Create a new document
(define-public (create-document (title (string-ascii 100)))
  (let
    (
      (document-id (var-get next-document-id))
      (caller tx-sender)
    )
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)

    (map-set documents
      { document-id: document-id }
      {
        title: title,
        primary-author: caller,
        created-at: block-height,
        last-modified: block-height,
        is-locked: false,
        total-authors: u1,
        version: u1
      }
    )

    (map-set document-authors
      { document-id: document-id, author: caller }
      {
        added-at: block-height,
        contribution-weight: u100,
        can-edit: true,
        can-invite: true,
        last-activity: block-height
      }
    )

    (map-set author-documents
      { author: caller, document-id: document-id }
      { is-active: true }
    )

    (var-set next-document-id (+ document-id u1))
    (ok document-id)
  )
)

;; Add a co-author to a document
(define-public (add-co-author (document-id uint) (new-author principal) (contribution-weight uint))
  (let
    (
      (document-data (unwrap! (map-get? documents { document-id: document-id }) ERR-DOCUMENT-NOT-FOUND))
      (caller-auth (unwrap! (map-get? document-authors { document-id: document-id, author: tx-sender }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (not (get is-locked document-data)) ERR-DOCUMENT-LOCKED)
    (asserts! (get can-invite caller-auth) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? document-authors { document-id: document-id, author: new-author })) ERR-ALREADY-AUTHOR)
    (asserts! (and (> contribution-weight u0) (<= contribution-weight u100)) ERR-INVALID-INPUT)

    (map-set document-authors
      { document-id: document-id, author: new-author }
      {
        added-at: block-height,
        contribution-weight: contribution-weight,
        can-edit: true,
        can-invite: false,
        last-activity: block-height
      }
    )

    (map-set author-documents
      { author: new-author, document-id: document-id }
      { is-active: true }
    )

    (map-set documents
      { document-id: document-id }
      (merge document-data {
        total-authors: (+ (get total-authors document-data) u1),
        last-modified: block-height
      })
    )

    (ok true)
  )
)

;; Update document version
(define-public (update-document (document-id uint) (content-hash (string-ascii 64)) (description (string-ascii 200)))
  (let
    (
      (document-data (unwrap! (map-get? documents { document-id: document-id }) ERR-DOCUMENT-NOT-FOUND))
      (author-data (unwrap! (map-get? document-authors { document-id: document-id, author: tx-sender }) ERR-NOT-AUTHORIZED))
      (new-version (+ (get version document-data) u1))
    )
    (asserts! (not (get is-locked document-data)) ERR-DOCUMENT-LOCKED)
    (asserts! (get can-edit author-data) ERR-NOT-AUTHORIZED)
    (asserts! (> (len content-hash) u0) ERR-INVALID-INPUT)

    (map-set document-versions
      { document-id: document-id, version: new-version }
      {
        content-hash: content-hash,
        author: tx-sender,
        timestamp: block-height,
        description: description
      }
    )

    (map-set documents
      { document-id: document-id }
      (merge document-data {
        version: new-version,
        last-modified: block-height
      })
    )

    (map-set document-authors
      { document-id: document-id, author: tx-sender }
      (merge author-data { last-activity: block-height })
    )

    (ok new-version)
  )
)

;; Lock/unlock document
(define-public (toggle-document-lock (document-id uint))
  (let
    (
      (document-data (unwrap! (map-get? documents { document-id: document-id }) ERR-DOCUMENT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get primary-author document-data)) ERR-NOT-AUTHORIZED)

    (map-set documents
      { document-id: document-id }
      (merge document-data {
        is-locked: (not (get is-locked document-data)),
        last-modified: block-height
      })
    )
    (ok (not (get is-locked document-data)))
  )
)

;; Update author permissions
(define-public (update-author-permissions (document-id uint) (author principal) (can-edit bool) (can-invite bool))
  (let
    (
      (document-data (unwrap! (map-get? documents { document-id: document-id }) ERR-DOCUMENT-NOT-FOUND))
      (author-data (unwrap! (map-get? document-authors { document-id: document-id, author: author }) ERR-AUTHOR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get primary-author document-data)) ERR-NOT-AUTHORIZED)

    (map-set document-authors
      { document-id: document-id, author: author }
      (merge author-data {
        can-edit: can-edit,
        can-invite: can-invite
      })
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get document information
(define-read-only (get-document (document-id uint))
  (map-get? documents { document-id: document-id })
)

;; Get author information for a document
(define-read-only (get-document-author (document-id uint) (author principal))
  (map-get? document-authors { document-id: document-id, author: author })
)

;; Check if user is author of document
(define-read-only (is-document-author (document-id uint) (author principal))
  (is-some (map-get? document-authors { document-id: document-id, author: author }))
)

;; Get document version
(define-read-only (get-document-version (document-id uint) (version uint))
  (map-get? document-versions { document-id: document-id, version: version })
)

;; Get next document ID
(define-read-only (get-next-document-id)
  (var-get next-document-id)
)

;; Check if author can edit document
(define-read-only (can-edit-document (document-id uint) (author principal))
  (match (map-get? document-authors { document-id: document-id, author: author })
    author-data (get can-edit author-data)
    false
  )
)
