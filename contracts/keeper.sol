// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract TokenLock {
    struct Lock {
        uint256 id;
        uint256 amount;
        uint256 unlockTime;
    }

    IERC20 public immutable token;
    uint256 private nextLockId = 1;

    mapping(address => Lock[]) private userLocks;
    mapping(address => mapping(uint256 => uint256)) private lockIndexes;

    event TokensLocked(address indexed user, uint256 indexed lockId, uint256 amount, uint256 unlockTime);
    event TokensUnlocked(address indexed user, uint256 indexed lockId, uint256 amount);
    event PartialUnlock(address indexed user, uint256 indexed lockId, uint256 amount, uint256 remaining);
    event LockExtended(address indexed user, uint256 indexed lockId, uint256 newUnlockTime);

    error InvalidAmount();
    error InvalidLockPeriod();
    error InvalidTokenAddress();
    error LockNotFound();
    error TokensStillLocked(uint256 unlockTime);
    error TransferFailed();
    error InsufficientBalance();

    constructor(address _tokenAddress) {
        if (_tokenAddress == address(0)) revert InvalidTokenAddress();
        token = IERC20(_tokenAddress);
    }

    function lockTokens(uint256 _amount, uint256 _timeInSeconds) external {
        if (_amount == 0) revert InvalidAmount();
        if (_timeInSeconds == 0) revert InvalidLockPeriod();

        uint256 unlockTime = block.timestamp + _timeInSeconds;
        uint256 lockId = nextLockId++;

        userLocks[msg.sender].push(Lock(lockId, _amount, unlockTime));
        lockIndexes[msg.sender][lockId] = userLocks[msg.sender].length - 1;

        if (!token.transferFrom(msg.sender, address(this), _amount)) revert TransferFailed();
        emit TokensLocked(msg.sender, lockId, _amount, unlockTime);
    }

    function unlockTokens(uint256 _lockId) external {
        Lock[] storage locks = userLocks[msg.sender];
        uint256 index = lockIndexes[msg.sender][_lockId];

        if (index >= locks.length || locks[index].id != _lockId) revert LockNotFound();
        if (block.timestamp < locks[index].unlockTime) revert TokensStillLocked(locks[index].unlockTime);

        uint256 amountToUnlock = locks[index].amount;
        _removeLock(msg.sender, index);

        if (!token.transfer(msg.sender, amountToUnlock)) revert TransferFailed();
        emit TokensUnlocked(msg.sender, _lockId, amountToUnlock);
    }

    function partialUnlock(uint256 _lockId, uint256 _amount) external {
        Lock[] storage locks = userLocks[msg.sender];
        uint256 index = lockIndexes[msg.sender][_lockId];

        if (index >= locks.length || locks[index].id != _lockId) revert LockNotFound();
        if (block.timestamp < locks[index].unlockTime) revert TokensStillLocked(locks[index].unlockTime);
        if (_amount == 0 || _amount > locks[index].amount) revert InvalidAmount();

        locks[index].amount -= _amount;

        if (!token.transfer(msg.sender, _amount)) revert TransferFailed();
        emit PartialUnlock(msg.sender, _lockId, _amount, locks[index].amount);

        if (locks[index].amount == 0) {
            _removeLock(msg.sender, index);
        }
    }

    function extendLockTime(uint256 _lockId, uint256 _additionalTime) external {
        if (_additionalTime == 0) revert InvalidLockPeriod();

        Lock[] storage locks = userLocks[msg.sender];
        uint256 index = lockIndexes[msg.sender][_lockId];

        if (index >= locks.length || locks[index].id != _lockId) revert LockNotFound();

        locks[index].unlockTime += _additionalTime;
        emit LockExtended(msg.sender, _lockId, locks[index].unlockTime);
    }

    function getUserLocks(address _user) external view returns (Lock[] memory) {
        return userLocks[_user];
    }

    function emergencyWithdraw(uint256 _lockId) external {
        Lock[] storage locks = userLocks[msg.sender];
        uint256 index = lockIndexes[msg.sender][_lockId];

        if (index >= locks.length || locks[index].id != _lockId) revert LockNotFound();

        uint256 amountToUnlock = locks[index].amount;
        _removeLock(msg.sender, index);

        if (!token.transfer(msg.sender, amountToUnlock)) revert TransferFailed();
        emit TokensUnlocked(msg.sender, _lockId, amountToUnlock);
    }

    function _removeLock(address _user, uint256 _index) private {
        Lock[] storage locks = userLocks[_user];
        uint256 lastIndex = locks.length - 1;

        if (_index != lastIndex) {
            locks[_index] = locks[lastIndex];
            lockIndexes[_user][locks[_index].id] = _index;
        }

        locks.pop();
        delete lockIndexes[_user][locks[_index].id];
    }

    function getContractBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function withdrawExcessTokens(uint256 _amount) external {
        uint256 contractBalance = token.balanceOf(address(this));
        uint256 totalLocked = getTotalLockedTokens();

        if (contractBalance - totalLocked < _amount) revert InsufficientBalance();

        if (!token.transfer(msg.sender, _amount)) revert TransferFailed();
    }

    function getTotalLockedTokens() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < userLocks[msg.sender].length; i++) {
            total += userLocks[msg.sender][i].amount;
        }
        return total;
    }
}