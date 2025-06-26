;; Deadline Enforcer Smart Contract
;; A robust contract for managing tasks with deadlines, penalties, and rewards

;; Constants
(define-constant contract-owner tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-DEADLINE-PASSED (err u103))
(define-constant ERR-INVALID-DEADLINE (err u104))
(define-constant ERR-INSUFFICIENT-FUNDS (err u105))
(define-constant ERR-UNAUTHORIZED (err u106))
(define-constant ERR-ALREADY-COMPLETED (err u107))
(define-constant ERR-NOT-COMPLETED (err u108))
(define-constant ERR-INVALID-AMOUNT (err u109))
(define-constant ERR-TASK-CANCELLED (err u110))
(define-constant ERR-ALREADY-CLAIMED (err u111))
(define-constant ERR-NO-PENALTY (err u112))
(define-constant ERR-INVALID-PRINCIPAL (err u113))
(define-constant ERR-INVALID-STRING (err u114))

;; Data Variables
(define-data-var task-counter uint u0)
(define-data-var total-fees-collected uint u0)
(define-data-var platform-fee-percentage uint u250) ;; 2.5% = 250 basis points

;; Data Maps
(define-map tasks
    uint 
    {
        creator: principal,
        assignee: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        deadline: uint,
        reward-amount: uint,
        penalty-amount: uint,
        status: (string-ascii 20), ;; "pending", "completed", "expired", "cancelled"
        completion-time: (optional uint),
        evidence-url: (optional (string-ascii 200)),
        arbiter: (optional principal)
    }
)

(define-map task-deposits
    uint
    {
        creator-deposit: uint,
        assignee-deposit: uint,
        total-deposit: uint
    }
)

(define-map user-stats
    principal
    {
        tasks-created: uint,
        tasks-completed: uint,
        tasks-failed: uint,
        total-rewards-earned: uint,
        total-penalties-paid: uint,
        reputation-score: uint
    }
)

(define-map task-extensions
    uint
    {
        extension-count: uint,
        last-extension-time: uint,
        total-extension-duration: uint
    }
)

(define-map dispute-resolutions
    uint
    {
        disputed: bool,
        dispute-reason: (optional (string-ascii 200)),
        resolution: (optional (string-ascii 200)),
        resolved-by: (optional principal),
        resolution-time: (optional uint)
    }
)

;; Private Functions
(define-private (calculate-fee (amount uint))
    (/ (* amount (var-get platform-fee-percentage)) u10000)
)

(define-private (update-user-stats-on-creation (user principal))
    (let ((current-stats (default-to 
            {tasks-created: u0, tasks-completed: u0, tasks-failed: u0, 
             total-rewards-earned: u0, total-penalties-paid: u0, reputation-score: u100}
            (map-get? user-stats user))))
        (map-set user-stats user 
            (merge current-stats {tasks-created: (+ (get tasks-created current-stats) u1)}))
    )
)

(define-private (update-user-stats-on-completion (user principal) (reward uint))
    (let ((current-stats (default-to 
            {tasks-created: u0, tasks-completed: u0, tasks-failed: u0, 
             total-rewards-earned: u0, total-penalties-paid: u0, reputation-score: u100}
            (map-get? user-stats user))))
        (map-set user-stats user 
            (merge current-stats {
                tasks-completed: (+ (get tasks-completed current-stats) u1),
                total-rewards-earned: (+ (get total-rewards-earned current-stats) reward),
                reputation-score: (+ (get reputation-score current-stats) u10)
            }))
    )
)

(define-private (update-user-stats-on-failure (user principal) (penalty uint))
    (let ((current-stats (default-to 
            {tasks-created: u0, tasks-completed: u0, tasks-failed: u0, 
             total-rewards-earned: u0, total-penalties-paid: u0, reputation-score: u100}
            (map-get? user-stats user))))
        (map-set user-stats user 
            (merge current-stats {
                tasks-failed: (+ (get tasks-failed current-stats) u1),
                total-penalties-paid: (+ (get total-penalties-paid current-stats) penalty),
                reputation-score: (if (> (get reputation-score current-stats) u10)
                    (- (get reputation-score current-stats) u10)
                    u0)
            }))
    )
)

;; Private function to validate arbiter
(define-private (validate-arbiter (arbiter (optional principal)) (creator principal) (assignee principal))
    (match arbiter
        arb (if (and (not (is-eq arb creator)) (not (is-eq arb assignee)))
                (some arb)
                none)
        ;; If no arbiter provided, return none
        none))

;; Public Functions

;; Create a new task with deadline
(define-public (create-task 
    (assignee principal) 
    (title (string-ascii 100)) 
    (description (string-ascii 500))
    (deadline uint)
    (reward-amount uint)
    (penalty-amount uint)
    (arbiter (optional principal)))
    (let ((task-id (+ (var-get task-counter) u1))
          (creator-deposit reward-amount)
          (platform-fee (calculate-fee reward-amount)))
        ;; Validations
        (asserts! (> deadline block-height) ERR-INVALID-DEADLINE)
        (asserts! (> reward-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= penalty-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (not (is-eq assignee tx-sender)) ERR-INVALID-PRINCIPAL)
        (asserts! (> (len title) u0) ERR-INVALID-STRING)
        (asserts! (> (len description) u0) ERR-INVALID-STRING)
        
        ;; Validate arbiter using private function
        (let ((validated-arbiter (validate-arbiter arbiter tx-sender assignee)))
            
            ;; Additional validation for arbiter
            (asserts! (match validated-arbiter
                        arb (and (not (is-eq arb tx-sender)) (not (is-eq arb assignee)))
                        true) ERR-INVALID-PRINCIPAL)
        
        ;; Transfer creator deposit (reward + platform fee)
        (try! (stx-transfer? (+ creator-deposit platform-fee) tx-sender (as-contract tx-sender)))
        
        ;; Create task with all fields
        (map-set tasks task-id {
            creator: tx-sender,
            assignee: assignee,
            title: title,
            description: description,
            deadline: deadline,
            reward-amount: reward-amount,
            penalty-amount: penalty-amount,
            status: "pending",
            completion-time: none,
            evidence-url: none,
            arbiter: validated-arbiter
        })
        ;; Set initial deposits
        (map-set task-deposits task-id {
            creator-deposit: creator-deposit,
            assignee-deposit: u0,
            total-deposit: creator-deposit
        })
        
        ;; Initialize extension tracking
        (map-set task-extensions task-id {
            extension-count: u0,
            last-extension-time: block-height,
            total-extension-duration: u0
        })
        
        ;; Update stats
        (update-user-stats-on-creation tx-sender)
        
        ;; Update counters
        (var-set task-counter task-id)
        (var-set total-fees-collected (+ (var-get total-fees-collected) platform-fee))
        
        (ok task-id)
        )
    )
)

;; Accept a task (assignee must deposit penalty amount)
(define-public (accept-task (task-id uint))
    (let ((task (unwrap! (map-get? tasks task-id) ERR-NOT-FOUND))
          (deposits (unwrap! (map-get? task-deposits task-id) ERR-NOT-FOUND)))
        ;; Validations
        (asserts! (is-eq (get assignee task) tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status task) "pending") ERR-ALREADY-COMPLETED)
        (asserts! (< block-height (get deadline task)) ERR-DEADLINE-PASSED)
        (asserts! (is-eq (get assignee-deposit deposits) u0) ERR-ALREADY-EXISTS)
        
        ;; Transfer penalty deposit from assignee if required
        (if (> (get penalty-amount task) u0)
            (try! (stx-transfer? (get penalty-amount task) tx-sender (as-contract tx-sender)))
            true
        )
        
        ;; Update deposits
        (map-set task-deposits task-id 
            (merge deposits {
                assignee-deposit: (get penalty-amount task),
                total-deposit: (+ (get total-deposit deposits) (get penalty-amount task))
            })
        )
        
        (ok true)
    )
)

;; Submit task completion
(define-public (complete-task (task-id uint) (evidence-url (string-ascii 200)))
    (let ((task (unwrap! (map-get? tasks task-id) ERR-NOT-FOUND)))
        ;; Validations
        (asserts! (is-eq (get assignee task) tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status task) "pending") ERR-ALREADY-COMPLETED)
        (asserts! (<= block-height (get deadline task)) ERR-DEADLINE-PASSED)
        (asserts! (> (len evidence-url) u0) ERR-INVALID-STRING)
        
        ;; Update task
        (map-set tasks task-id 
            (merge task {
                status: "completed",
                completion-time: (some block-height),
                evidence-url: (some evidence-url)
            })
        )
        
        (ok true)
    )
)

;; Verify and release payment for completed task
(define-public (verify-and-release-payment (task-id uint))
    (let ((task (unwrap! (map-get? tasks task-id) ERR-NOT-FOUND))
          (deposits (unwrap! (map-get? task-deposits task-id) ERR-NOT-FOUND)))
        ;; Validations
        (asserts! (or (is-eq (get creator task) tx-sender) 
                     (is-eq (some tx-sender) (get arbiter task))) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status task) "completed") ERR-NOT-COMPLETED)
        
        ;; Calculate payments
        (let ((reward (get reward-amount task))
              (penalty-return (get assignee-deposit deposits)))
            
            ;; Transfer reward to assignee
            (try! (as-contract (stx-transfer? reward tx-sender (get assignee task))))
            
            ;; Return penalty deposit to assignee if any
            (if (> penalty-return u0)
                (try! (as-contract (stx-transfer? penalty-return tx-sender (get assignee task))))
                true
            )
            
            ;; Update user stats
            (update-user-stats-on-completion (get assignee task) reward)
            
            (ok true)
        )
    )
)

;; Claim penalty for expired task
(define-public (claim-penalty (task-id uint))
    (let ((task (unwrap! (map-get? tasks task-id) ERR-NOT-FOUND))
          (deposits (unwrap! (map-get? task-deposits task-id) ERR-NOT-FOUND)))
        ;; Validations
        (asserts! (is-eq (get creator task) tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status task) "pending") ERR-ALREADY-COMPLETED)
        (asserts! (> block-height (get deadline task)) ERR-DEADLINE-PASSED)
        (asserts! (> (get assignee-deposit deposits) u0) ERR-NO-PENALTY)
        
        ;; Update task status
        (map-set tasks task-id (merge task {status: "expired"}))
        
        ;; Transfer penalty to creator and return reward deposit
        (let ((penalty (get assignee-deposit deposits))
              (reward-return (get creator-deposit deposits)))
            
            ;; Transfer penalty to creator
            (try! (as-contract (stx-transfer? penalty tx-sender tx-sender)))
            
            ;; Return reward deposit to creator
            (try! (as-contract (stx-transfer? reward-return tx-sender tx-sender)))
            
            ;; Update user stats
            (update-user-stats-on-failure (get assignee task) penalty)
            
            (ok true)
        )
    )
)

;; Request deadline extension
(define-public (request-extension (task-id uint) (new-deadline uint) (reason (string-ascii 200)))
    (let ((task (unwrap! (map-get? tasks task-id) ERR-NOT-FOUND))
          (extensions (unwrap! (map-get? task-extensions task-id) ERR-NOT-FOUND)))
        ;; Validations
        (asserts! (is-eq (get assignee task) tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status task) "pending") ERR-ALREADY-COMPLETED)
        (asserts! (> new-deadline (get deadline task)) ERR-INVALID-DEADLINE)
        (asserts! (< (get extension-count extensions) u3) ERR-ALREADY-EXISTS) ;; Max 3 extensions
        (asserts! (> (len reason) u0) ERR-INVALID-STRING)
        
        ;; Store extension request (in production, this would need creator approval)
        ;; For now, auto-approve if within reasonable limits
        (let ((extension-duration (- new-deadline (get deadline task))))
            (if (<= extension-duration u1440) ;; Max 1440 blocks (~10 days) per extension
                (begin
                    ;; Update task deadline
                    (map-set tasks task-id (merge task {deadline: new-deadline}))
                    
                    ;; Update extension tracking
                    (map-set task-extensions task-id {
                        extension-count: (+ (get extension-count extensions) u1),
                        last-extension-time: block-height,
                        total-extension-duration: (+ (get total-extension-duration extensions) extension-duration)
                    })
                    
                    (ok true)
                )
                ERR-INVALID-DEADLINE
            )
        )
    )
)

;; Cancel task (only before acceptance)
(define-public (cancel-task (task-id uint))
    (let ((task (unwrap! (map-get? tasks task-id) ERR-NOT-FOUND))
          (deposits (unwrap! (map-get? task-deposits task-id) ERR-NOT-FOUND)))
        ;; Validations
        (asserts! (is-eq (get creator task) tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status task) "pending") ERR-ALREADY-COMPLETED)
        (asserts! (is-eq (get assignee-deposit deposits) u0) ERR-ALREADY-EXISTS) ;; Can't cancel after acceptance
        
        ;; Update status
        (map-set tasks task-id (merge task {status: "cancelled"}))
        
        ;; Return creator deposit minus cancellation fee
        (let ((cancellation-fee (calculate-fee (get creator-deposit deposits)))
              (refund-amount (- (get creator-deposit deposits) cancellation-fee)))
            
            (try! (as-contract (stx-transfer? refund-amount tx-sender tx-sender)))
            (var-set total-fees-collected (+ (var-get total-fees-collected) cancellation-fee))
            
            (ok true)
        )
    )
)

;; Raise dispute
(define-public (raise-dispute (task-id uint) (reason (string-ascii 200)))
    (let ((task (unwrap! (map-get? tasks task-id) ERR-NOT-FOUND)))
        ;; Validations
        (asserts! (or (is-eq (get creator task) tx-sender) 
                     (is-eq (get assignee task) tx-sender)) ERR-UNAUTHORIZED)
        (asserts! (is-some (get arbiter task)) ERR-UNAUTHORIZED) ;; Need arbiter for disputes
        (asserts! (> (len reason) u0) ERR-INVALID-STRING)
        
        ;; Create dispute record
        (map-set dispute-resolutions task-id {
            disputed: true,
            dispute-reason: (some reason),
            resolution: none,
            resolved-by: none,
            resolution-time: none
        })
        
        (ok true)
    )
)

;; Resolve dispute (arbiter only)
(define-public (resolve-dispute (task-id uint) (resolution (string-ascii 200)) (favor-assignee bool))
    (let ((task (unwrap! (map-get? tasks task-id) ERR-NOT-FOUND))
          (dispute (unwrap! (map-get? dispute-resolutions task-id) ERR-NOT-FOUND))
          (deposits (unwrap! (map-get? task-deposits task-id) ERR-NOT-FOUND)))
        ;; Validations
        (asserts! (is-eq (some tx-sender) (get arbiter task)) ERR-UNAUTHORIZED)
        (asserts! (get disputed dispute) ERR-NOT-FOUND)
        (asserts! (> (len resolution) u0) ERR-INVALID-STRING)
        
        ;; Update dispute record
        (map-set dispute-resolutions task-id 
            (merge dispute {
                resolution: (some resolution),
                resolved-by: (some tx-sender),
                resolution-time: (some block-height)
            })
        )
        
        ;; Distribute funds based on resolution
        (if favor-assignee
            ;; Favor assignee - release payment
            (begin
                (try! (as-contract (stx-transfer? (get reward-amount task) tx-sender (get assignee task))))
                (if (> (get assignee-deposit deposits) u0)
                    (try! (as-contract (stx-transfer? (get assignee-deposit deposits) tx-sender (get assignee task))))
                    true
                )
            )
            ;; Favor creator - return deposits
            (begin
                (try! (as-contract (stx-transfer? (get creator-deposit deposits) tx-sender (get creator task))))
                (if (> (get assignee-deposit deposits) u0)
                    (try! (as-contract (stx-transfer? (get assignee-deposit deposits) tx-sender (get creator task))))
                    true
                )
            )
        )
        
        (ok true)
    )
)

;; Read-only functions

(define-read-only (get-task (task-id uint))
    (map-get? tasks task-id)
)

(define-read-only (get-task-deposits (task-id uint))
    (map-get? task-deposits task-id)
)

(define-read-only (get-user-stats (user principal))
    (default-to 
        {tasks-created: u0, tasks-completed: u0, tasks-failed: u0, 
         total-rewards-earned: u0, total-penalties-paid: u0, reputation-score: u100}
        (map-get? user-stats user)
    )
)

(define-read-only (get-task-extensions (task-id uint))
    (map-get? task-extensions task-id)
)

(define-read-only (get-dispute-info (task-id uint))
    (map-get? dispute-resolutions task-id)
)

(define-read-only (get-platform-fee-percentage)
    (ok (var-get platform-fee-percentage))
)

(define-read-only (get-total-fees-collected)
    (ok (var-get total-fees-collected))
)

(define-read-only (get-task-count)
    (ok (var-get task-counter))
)

;; Admin functions

(define-public (set-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
        (asserts! (<= new-fee u1000) ERR-INVALID-AMOUNT) ;; Max 10%
        (var-set platform-fee-percentage new-fee)
        (ok true)
    )
)

(define-public (withdraw-fees (amount uint) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
        (asserts! (<= amount (var-get total-fees-collected)) ERR-INSUFFICIENT-FUNDS)
        (asserts! (not (is-eq recipient (as-contract tx-sender))) ERR-INVALID-PRINCIPAL)
        (try! (as-contract (stx-transfer? amount tx-sender recipient)))
        (var-set total-fees-collected (- (var-get total-fees-collected) amount))
        (ok true)
    )
)