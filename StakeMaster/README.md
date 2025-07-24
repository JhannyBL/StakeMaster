# StakeMaster - Decentralized Token Staking Platform

StakeMaster is a comprehensive decentralized staking platform built on the Stacks blockchain, enabling users to stake tokens in reward vaults and earn yields over time.

## Overview

StakeMaster provides a secure and efficient way to:
- Create customizable staking vaults with different reward structures
- Stake tokens and earn yields based on block-by-block calculations
- Harvest accumulated rewards with transparent fee structures
- Manage multiple staking positions across different vaults

## Key Features

### 🏦 Flexible Vault System
- Create multiple reward vaults with different token pairs
- Configurable yield rates per block
- Enable/disable vaults as needed
- Real-time yield calculations

### 💰 Yield Generation
- Continuous yield accrual based on staking duration
- Pro-rata reward distribution among participants
- Compound-friendly architecture
- Transparent fee structure (3% service fee)

### 🔒 Security Features
- Admin-only vault management functions
- Emergency recovery mechanisms
- Secure token transfers using SIP-10 standard
- Input validation and error handling

### 📊 Analytics & Monitoring
- Real-time pending yield calculations
- Vault performance analytics
- Participant position tracking
- Historical staking data

## Contract Functions

### Core Staking Functions

#### `deposit-tokens(vault-id, amount, token-contract)`
Stake tokens in a specific vault to start earning yields.

#### `withdraw-tokens(vault-id, amount, token-contract)`
Withdraw staked tokens from a vault (yields are preserved).

#### `harvest-yield(vault-id, yield-token-contract)`
Claim accumulated yields from a vault (minus service fee).

### Vault Management (Admin Only)

#### `create-vault(staking-token, yield-token, yield-per-block)`
Create a new staking vault with specified parameters.

#### `fund-vault(vault-id, amount, yield-token-contract)`
Add yield tokens to a vault for distribution.

#### `toggle-vault-status(vault-id)`
Enable or disable a vault for new deposits.

#### `modify-yield-rate(vault-id, new-rate)`
Update the yield rate for a specific vault.

### View Functions

#### `get-vault-details(vault-id)`
Retrieve complete information about a vault.

#### `get-participant-info(participant, vault-id)`
Get staking position details for a specific participant.

#### `calculate-pending-yield(participant, vault-id)`
Calculate current pending yields for a participant.

#### `get-vault-analytics(vault-id)`
Get comprehensive analytics for a vault.

## Usage Examples

### Creating a Vault (Admin)
```clarity
(contract-call? .stakemaster create-vault 
  'SP1ABC...TOKEN-CONTRACT    ;; Staking token
  'SP1DEF...REWARD-CONTRACT   ;; Yield token
  u1000                       ;; 1000 yield units per block
)
```

### Staking Tokens
```clarity
(contract-call? .stakemaster deposit-tokens 
  u1                          ;; Vault ID
  u1000000                    ;; Amount to stake
  'SP1ABC...TOKEN-CONTRACT    ;; Token contract
)
```

### Harvesting Yields
```clarity
(contract-call? .stakemaster harvest-yield 
  u1                          ;; Vault ID
  'SP1DEF...REWARD-CONTRACT   ;; Yield token contract
)
```

## Fee Structure

- **Service Fee**: 3% (300 basis points) on harvested yields
- **Max Fee Cap**: 15% (adjustable by admin)
- All fees are collected by the platform admin

## Security Considerations

1. **Admin Controls**: Critical functions are restricted to admin-only access
2. **Input Validation**: All user inputs are validated before processing
3. **Safe Math**: All calculations use safe arithmetic to prevent overflows
4. **Token Standards**: Full compliance with SIP-10 token standard
5. **Emergency Functions**: Admin can recover funds in emergency situations

## Architecture

The contract uses a vault-based architecture where:
- Each vault has its own staking and reward tokens
- Yields are calculated per-block and accumulated continuously
- Participants can have positions in multiple vaults simultaneously
- Real-time calculations ensure fair reward distribution

## Integration

StakeMaster can be integrated with:
- DeFi protocols for automated yield strategies
- Portfolio management interfaces
- Analytics dashboards
- Multi-signature wallet systems

## Contributing

Contributions are welcome! 