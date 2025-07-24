;; StakeMaster - Decentralized Token Staking Platform on Stacks
;; A comprehensive platform for staking tokens in reward pools and earning yields

;; Define SIP-10 trait locally
(define-trait sip-10-trait
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

;; Constants
(define-constant admin tx-sender)
(define-constant err-admin-only (err u100))
(define-constant err-unauthorized (err u101))
(define-constant err-invalid-value (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-vault-not-found (err u104))
(define-constant err-already-participating (err u105))
(define-constant err-not-participating (err u106))
(define-constant err-lockup-active (err u107))
(define-constant err-transfer-error (err u108))

;; Data Variables
(define-data-var total-vaults uint u0)
(define-data-var service-fee uint u300) ;; 3% fee (300 basis points)

;; Data Maps
(define-map reward-vaults 
  { vault-id: uint }
  {
    staking-token: principal,
    yield-token: principal,
    total-deposited: uint,
    yield-per-block: uint, ;; yields per block
    last-calculation-block: uint,
    yield-per-token-accumulated: uint,
    enabled: bool
  }
)

(define-map participant-deposits
  { participant: principal, vault-id: uint }
  {
    deposit-amount: uint,
    yield-per-token-captured: uint,
    accumulated-yield: uint,
    deposit-block: uint
  }
)

(define-map participant-yields
  { participant: principal, vault-id: uint }
  uint
)

;; Vault Management Functions
(define-public (create-vault (staking-token principal) (yield-token principal) (yield-per-block uint))
  (let ((vault-id (+ (var-get total-vaults) u1)))
    (asserts! (is-eq tx-sender admin) err-admin-only)
    (asserts! (> yield-per-block u0) err-invalid-value)
    
    (map-set reward-vaults 
      { vault-id: vault-id }
      {
        staking-token: staking-token,
        yield-token: yield-token,
        total-deposited: u0,
        yield-per-block: yield-per-block,
        last-calculation-block: stacks-block-height,
        yield-per-token-accumulated: u0,
        enabled: true
      }
    )
    (var-set total-vaults vault-id)
    (ok vault-id)
  )
)

(define-public (refresh-vault (vault-id uint))
  (let (
    (vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) err-vault-not-found))
    (total-deposited (get total-deposited vault-info))
    (blocks-elapsed (- stacks-block-height (get last-calculation-block vault-info)))
    (yield-increment 
      (if (> total-deposited u0)
        (/ (* blocks-elapsed (get yield-per-block vault-info) u1000000) total-deposited)
        u0
      )
    )
    (updated-yield-per-token (+ (get yield-per-token-accumulated vault-info) yield-increment))
  )
    (map-set reward-vaults 
      { vault-id: vault-id }
      (merge vault-info {
        yield-per-token-accumulated: updated-yield-per-token,
        last-calculation-block: stacks-block-height
      })
    )
    (ok updated-yield-per-token)
  )
)

;; Staking Functions
(define-public (deposit-tokens (vault-id uint) (amount uint) (token-contract <sip-10-trait>))
  (let (
    (vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) err-vault-not-found))
    (participant-info (default-to 
      { deposit-amount: u0, yield-per-token-captured: u0, accumulated-yield: u0, deposit-block: stacks-block-height }
      (map-get? participant-deposits { participant: tx-sender, vault-id: vault-id })
    ))
  )
    (asserts! (get enabled vault-info) err-unauthorized)
    (asserts! (> amount u0) err-invalid-value)
    (asserts! (is-eq (contract-of token-contract) (get staking-token vault-info)) err-unauthorized)
    
    ;; Refresh vault calculations
    (try! (refresh-vault vault-id))
    
    ;; Calculate pending yields
    (let ((refreshed-vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) err-vault-not-found)))
      (let (
        (current-yield-per-token (get yield-per-token-accumulated refreshed-vault-info))
        (pending-yield 
          (if (> (get deposit-amount participant-info) u0)
            (/ (* (get deposit-amount participant-info) 
                  (- current-yield-per-token (get yield-per-token-captured participant-info))) 
               u1000000)
            u0
          )
        )
        (total-accumulated-yield (+ (get accumulated-yield participant-info) pending-yield))
      )
        
        ;; Transfer tokens to contract first
        (unwrap! (contract-call? token-contract transfer amount tx-sender (as-contract tx-sender) none) err-transfer-error)
        
        ;; Update participant deposit
        (map-set participant-deposits
          { participant: tx-sender, vault-id: vault-id }
          {
            deposit-amount: (+ (get deposit-amount participant-info) amount),
            yield-per-token-captured: current-yield-per-token,
            accumulated-yield: total-accumulated-yield,
            deposit-block: stacks-block-height
          }
        )
        
        ;; Update vault total deposited
        (map-set reward-vaults 
          { vault-id: vault-id }
          (merge refreshed-vault-info {
            total-deposited: (+ (get total-deposited refreshed-vault-info) amount)
          })
        )
        
        (ok true)
      )
    )
  )
)

(define-public (withdraw-tokens (vault-id uint) (amount uint) (token-contract <sip-10-trait>))
  (let (
    (vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) err-vault-not-found))
    (participant-info (unwrap! (map-get? participant-deposits { participant: tx-sender, vault-id: vault-id }) err-not-participating))
  )
    (asserts! (>= (get deposit-amount participant-info) amount) err-insufficient-funds)
    (asserts! (> amount u0) err-invalid-value)
    (asserts! (is-eq (contract-of token-contract) (get staking-token vault-info)) err-unauthorized)
    
    ;; Refresh vault calculations
    (try! (refresh-vault vault-id))
    
    (let ((refreshed-vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) err-vault-not-found)))
      (let (
        (current-yield-per-token (get yield-per-token-accumulated refreshed-vault-info))
        (pending-yield 
          (/ (* (get deposit-amount participant-info) 
                (- current-yield-per-token (get yield-per-token-captured participant-info))) 
             u1000000)
        )
        (total-accumulated-yield (+ (get accumulated-yield participant-info) pending-yield))
        (remaining-deposit (- (get deposit-amount participant-info) amount))
      )
        
        ;; Update participant deposit
        (map-set participant-deposits
          { participant: tx-sender, vault-id: vault-id }
          {
            deposit-amount: remaining-deposit,
            yield-per-token-captured: current-yield-per-token,
            accumulated-yield: total-accumulated-yield,
            deposit-block: (get deposit-block participant-info)
          }
        )
        
        ;; Update vault total deposited
        (map-set reward-vaults 
          { vault-id: vault-id }
          (merge refreshed-vault-info {
            total-deposited: (- (get total-deposited refreshed-vault-info) amount)
          })
        )
        
        ;; Transfer tokens back to participant
        (unwrap! (as-contract (contract-call? token-contract transfer amount (as-contract tx-sender) tx-sender none)) err-transfer-error)
        
        (ok true)
      )
    )
  )
)

(define-public (harvest-yield (vault-id uint) (yield-token-contract <sip-10-trait>))
  (let (
    (vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) err-vault-not-found))
    (participant-info (unwrap! (map-get? participant-deposits { participant: tx-sender, vault-id: vault-id }) err-not-participating))
  )
    (asserts! (is-eq (contract-of yield-token-contract) (get yield-token vault-info)) err-unauthorized)
    
    ;; Refresh vault calculations
    (try! (refresh-vault vault-id))
    
    (let ((refreshed-vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) err-vault-not-found)))
      (let (
        (current-yield-per-token (get yield-per-token-accumulated refreshed-vault-info))
        (pending-yield 
          (/ (* (get deposit-amount participant-info) 
                (- current-yield-per-token (get yield-per-token-captured participant-info))) 
             u1000000)
        )
        (total-yield (+ (get accumulated-yield participant-info) pending-yield))
        (service-fee-amount (/ (* total-yield (var-get service-fee)) u10000))
        (participant-yield-amount (- total-yield service-fee-amount))
      )
        
        (asserts! (> total-yield u0) err-invalid-value)
        
        ;; Update participant deposit
        (map-set participant-deposits
          { participant: tx-sender, vault-id: vault-id }
          {
            deposit-amount: (get deposit-amount participant-info),
            yield-per-token-captured: current-yield-per-token,
            accumulated-yield: u0,
            deposit-block: (get deposit-block participant-info)
          }
        )
        
        ;; Transfer yield to participant (minus service fee)
        (unwrap! (as-contract (contract-call? yield-token-contract transfer participant-yield-amount (as-contract tx-sender) tx-sender none)) err-transfer-error)
        
        ;; Transfer service fee to admin
        (unwrap! (as-contract (contract-call? yield-token-contract transfer service-fee-amount (as-contract tx-sender) admin none)) err-transfer-error)
        
        (ok participant-yield-amount)
      )
    )
  )
)

;; Helper function to fund vaults (admin only)
(define-public (fund-vault (vault-id uint) (amount uint) (yield-token-contract <sip-10-trait>))
  (let ((vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) err-vault-not-found)))
    (asserts! (is-eq tx-sender admin) err-admin-only)
    (asserts! (is-eq (contract-of yield-token-contract) (get yield-token vault-info)) err-unauthorized)
    (asserts! (> amount u0) err-invalid-value)
    
    ;; Transfer yield tokens to contract
    (unwrap! (contract-call? yield-token-contract transfer amount tx-sender (as-contract tx-sender) none) err-transfer-error)
    (ok true)
  )
)

;; Emergency recovery function (admin only)
(define-public (emergency-recovery (vault-id uint) (amount uint) (token-contract <sip-10-trait>))
  (let ((vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) err-vault-not-found)))
    (asserts! (is-eq tx-sender admin) err-admin-only)
    
    ;; Transfer tokens back to admin
    (unwrap! (as-contract (contract-call? token-contract transfer amount (as-contract tx-sender) admin none)) err-transfer-error)
    (ok true)
  )
)

;; View Functions
(define-read-only (get-vault-details (vault-id uint))
  (map-get? reward-vaults { vault-id: vault-id })
)

(define-read-only (get-participant-info (participant principal) (vault-id uint))
  (map-get? participant-deposits { participant: participant, vault-id: vault-id })
)

(define-read-only (calculate-pending-yield (participant principal) (vault-id uint))
  (let (
    (vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) (err u0)))
    (participant-info (unwrap! (map-get? participant-deposits { participant: participant, vault-id: vault-id }) (err u0)))
    (blocks-elapsed (- stacks-block-height (get last-calculation-block vault-info)))
    (yield-increment 
      (if (> (get total-deposited vault-info) u0)
        (/ (* blocks-elapsed (get yield-per-block vault-info) u1000000) (get total-deposited vault-info))
        u0
      )
    )
    (projected-yield-per-token (+ (get yield-per-token-accumulated vault-info) yield-increment))
    (pending-yield 
      (/ (* (get deposit-amount participant-info) 
            (- projected-yield-per-token (get yield-per-token-captured participant-info))) 
         u1000000)
    )
  )
    (ok (+ (get accumulated-yield participant-info) pending-yield))
  )
)

(define-read-only (get-total-vaults)
  (var-get total-vaults)
)

(define-read-only (get-service-fee)
  (var-get service-fee)
)

(define-read-only (get-admin)
  admin
)

;; Vault analytics
(define-read-only (get-vault-analytics (vault-id uint))
  (let ((vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) (err u0))))
    (let (
      (blocks-elapsed (- stacks-block-height (get last-calculation-block vault-info)))
      (projected-yield-per-token 
        (if (> (get total-deposited vault-info) u0)
          (+ (get yield-per-token-accumulated vault-info)
             (/ (* blocks-elapsed (get yield-per-block vault-info) u1000000) (get total-deposited vault-info)))
          (get yield-per-token-accumulated vault-info)
        )
      )
    )
      (ok {
        total-deposited: (get total-deposited vault-info),
        yield-per-block: (get yield-per-block vault-info),
        projected-yield-per-token: projected-yield-per-token,
        enabled: (get enabled vault-info),
        last-calculation-block: (get last-calculation-block vault-info)
      })
    )
  )
)

;; Admin Functions
(define-public (update-service-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender admin) err-admin-only)
    (asserts! (<= new-fee u1500) err-invalid-value) ;; Max 15% fee
    (var-set service-fee new-fee)
    (ok true)
  )
)

(define-public (toggle-vault-status (vault-id uint))
  (let ((vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) err-vault-not-found)))
    (asserts! (is-eq tx-sender admin) err-admin-only)
    (map-set reward-vaults 
      { vault-id: vault-id }
      (merge vault-info { enabled: (not (get enabled vault-info)) })
    )
    (ok true)
  )
)

(define-public (modify-yield-rate (vault-id uint) (new-rate uint))
  (let ((vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) err-vault-not-found)))
    (asserts! (is-eq tx-sender admin) err-admin-only)
    (asserts! (> new-rate u0) err-invalid-value)
    
    ;; Refresh vault calculations before changing rate
    (try! (refresh-vault vault-id))
    
    (let ((refreshed-vault-info (unwrap! (map-get? reward-vaults { vault-id: vault-id }) err-vault-not-found)))
      (map-set reward-vaults 
        { vault-id: vault-id }
        (merge refreshed-vault-info { yield-per-block: new-rate })
      )
      (ok true)
    )
  )
)