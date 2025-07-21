# Decentralized Parking System Smart Contract

A comprehensive blockchain-based parking management system built on Stacks, enabling peer-to-peer parking spot rentals with integrated payment processing, dispute resolution, and rating systems.

## Overview

This smart contract creates a decentralized marketplace where parking spot owners can list their spaces and renters can reserve them with automatic payment processing. The system includes reputation management, dispute resolution, and platform fee collection.

## Features

### Core Functionality
- **Parking Spot Registration**: Owners can list their parking spaces with location and hourly rates
- **Reservation System**: Users can reserve spots for specific time periods
- **Automatic Payments**: STX payments are processed automatically with platform fees
- **Rating System**: Users can rate parking experiences (1-5 stars)
- **Dispute Resolution**: Built-in dispute filing and resolution mechanism
- **User Profiles**: Track user statistics, earnings, and reputation

### Security Features
- **Time-based Validations**: Prevents invalid reservation times
- **Authorization Checks**: Ensures only authorized users can modify data
- **Payment Escrow**: Secure payment handling through the contract
- **Dispute Windows**: Time-limited dispute filing (1 week)

## Contract Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `PLATFORM-FEE-PERCENTAGE` | 5% | Platform commission on transactions |
| `MIN-PARKING-FEE` | 1,000 µSTX | Minimum parking fee |
| `MAX-PARKING-FEE` | 10,000,000 µSTX | Maximum parking fee |
| `RESERVATION-TIMEOUT-BLOCKS` | 144 blocks (~24 hours) | Reservation expiration time |
| `DISPUTE-WINDOW-BLOCKS` | 1,008 blocks (~1 week) | Time limit for filing disputes |

## Data Structures

### Parking Spots
```clarity
{
  owner: principal,
  location: string-ascii 100,
  hourly-rate: uint,
  status: uint, // 0: Available, 1: Reserved, 2: Occupied, 3: Maintenance
  total-reservations: uint,
  total-earnings: uint,
  rating-sum: uint,
  rating-count: uint,
  created-at: uint,
  updated-at: uint
}
```

### Reservations
```clarity
{
  spot-id: uint,
  renter: principal,
  start-time: uint,
  end-time: uint,
  total-cost: uint,
  platform-fee: uint,
  status: uint, // 0: Active, 1: Completed, 2: Cancelled, 3: Disputed
  created-at: uint,
  completed-at: optional uint,
  dispute-reason: optional string-ascii 200
}
```

### User Profiles
```clarity
{
  total-spots-owned: uint,
  total-reservations: uint,
  reputation-score: uint,
  total-earned: uint,
  total-spent: uint,
  joined-at: uint
}
```

## Public Functions

### Parking Spot Management

#### `register-parking-spot`
```clarity
(register-parking-spot (location (string-ascii 100)) (hourly-rate uint))
```
Register a new parking spot for rent.

**Parameters:**
- `location`: Description of the parking spot location
- `hourly-rate`: Cost per hour in microSTX (1,000 - 10,000,000 µSTX)

**Returns:** `(ok spot-id)` on success

#### `update-parking-spot`
```clarity
(update-parking-spot (spot-id uint) (location (optional (string-ascii 100))) (hourly-rate (optional uint)))
```
Update parking spot details (owner only).

#### `set-spot-status`
```clarity
(set-spot-status (spot-id uint) (new-status uint))
```
Change parking spot status (owner only).
- `0`: Available
- `1`: Reserved
- `2`: Occupied
- `3`: Maintenance

### Reservation Management

#### `make-reservation`
```clarity
(make-reservation (spot-id uint) (start-time uint) (end-time uint))
```
Reserve a parking spot for a specific time period.

**Parameters:**
- `spot-id`: ID of the parking spot to reserve
- `start-time`: Reservation start time in block height
- `end-time`: Reservation end time in block height

**Returns:** `(ok reservation-id)` on success

#### `complete-reservation`
```clarity
(complete-reservation (reservation-id uint))
```
Mark a reservation as completed and release payment to spot owner.

#### `cancel-reservation`
```clarity
(cancel-reservation (reservation-id uint))
```
Cancel an active reservation before start time (renter only).

### Rating System

#### `rate-parking-spot`
```clarity
(rate-parking-spot (spot-id uint) (rating uint) (comment (optional (string-ascii 200))))
```
Rate a parking spot after use (1-5 stars).

### Dispute Management

#### `file-dispute`
```clarity
(file-dispute (reservation-id uint) (reason (string-ascii 200)))
```
File a dispute for a reservation within the dispute window.

## Read-Only Functions

### Information Retrieval

#### `get-parking-spot`
```clarity
(get-parking-spot (spot-id uint))
```
Get detailed information about a parking spot.

#### `get-reservation`
```clarity
(get-reservation (reservation-id uint))
```
Get reservation details.

#### `get-user-profile`
```clarity
(get-user-profile (user principal))
```
Get user profile information.

#### `get-spot-rating`
```clarity
(get-spot-rating (spot-id uint))
```
Get average rating for a parking spot.

#### `get-platform-stats`
```clarity
(get-platform-stats)
```
Get platform-wide statistics.

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 401 | `ERR-NOT-AUTHORIZED` | Unauthorized access attempt |
| 404 | `ERR-SPOT-NOT-FOUND` | Parking spot doesn't exist |
| 409 | `ERR-SPOT-ALREADY-EXISTS` | Parking spot already registered |
| 410 | `ERR-SPOT-NOT-AVAILABLE` | Parking spot not available for reservation |
| 411 | `ERR-INVALID-AMOUNT` | Invalid payment amount |
| 412 | `ERR-RESERVATION-EXPIRED` | Reservation has expired |
| 413 | `ERR-RESERVATION-NOT-FOUND` | Reservation doesn't exist |
| 414 | `ERR-INVALID-TIME-RANGE` | Invalid start/end time |
| 415 | `ERR-INSUFFICIENT-PAYMENT` | Insufficient payment provided |
| 416 | `ERR-TRANSFER-FAILED` | STX transfer failed |
| 417 | `ERR-DISPUTE-WINDOW-CLOSED` | Dispute filing window expired |
| 418 | `ERR-INVALID-STATUS` | Invalid status transition |
| 419 | `ERR-ALREADY-RATED` | User already rated this spot |
| 420 | `ERR-INVALID-RATING` | Rating must be between 1-5 |

## Usage Examples

### Register a Parking Spot
```clarity
(contract-call? .parking-contract register-parking-spot "Downtown Garage, Level 2, Spot A5" u5000)
```

### Make a Reservation
```clarity
;; Reserve spot #1 for 4 hours starting at block 1000
(contract-call? .parking-contract make-reservation u1 u1000 u1024)
```

### Rate a Parking Spot
```clarity
(contract-call? .parking-contract rate-parking-spot u1 u5 (some "Great spot, easy access!"))
```

## Deployment

1. Deploy the contract to Stacks blockchain
2. The deployer becomes the `CONTRACT-OWNER`
3. Users can immediately start registering parking spots

## Security Considerations

- **Payment Security**: All payments are held in escrow by the contract
- **Time Validation**: Prevents booking in the past or invalid time ranges
- **Authorization**: Each function checks user permissions
- **Rate Limiting**: Platform fee limits prevent excessive charges
- **Dispute Resolution**: Time-limited dispute window ensures fairness

## Platform Economics

- **Platform Fee**: 5% of each transaction
- **Minimum Fee**: 1,000 microSTX (~$0.001 at $1/STX)
- **Maximum Fee**: 10,000,000 microSTX (~$10 at $1/STX)
- **Cancellation**: Small fee retained for early cancellations