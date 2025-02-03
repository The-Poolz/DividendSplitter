// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DividendSplitter
 * @notice An ERC20 token (with snapshot functionality) that distributes ETH
 *         when a whitelisted address calls createSnapshot with a certain msg.value.
 *         Anyone can call claim(...) to withdraw on behalf of a token holder.
 *
 *         Key Features:
 *         - No fallback/receive, so ETH must be sent alongside createSnapshot().
 *         - Whitelisted addresses enforce who can create snapshots (avoiding spam).
 *         - A time-based minInterval ensures one snapshot per interval at most.
 */
contract DividendSplitter is ERC20Snapshot, Ownable {
    /// @notice Minimum interval (in seconds) between snapshots (default: 30 days).
    uint256 public minInterval = 30 days;

    /// @notice The last time a snapshot was created.
    uint256 public lastSnapshotTime;

    /// @notice Mapping of snapshotId => total ETH allocated at creation.
    mapping(uint256 => uint256) public snapshotIdToEth;

    /// @notice Prevents double claiming: snapshotId => (account => bool).
    mapping(uint256 => mapping(address => bool)) public claimed;

    /// @notice Whitelist for addresses allowed to call createSnapshot.
    mapping(address => bool) public isWhitelisted;

    /**
     * @dev The constructor is payable for an optional initial ETH deposit.
     *      (Not distributed unless you call createSnapshot with it.)
     * @param name_  The ERC20 name (e.g. "DividendToken")
     * @param symbol_ The ERC20 symbol (e.g. "DVD")
     */
    constructor(
        string memory name_,
        string memory symbol_
    ) payable ERC20(name_, symbol_) {
        lastSnapshotTime = block.timestamp;
        // Optionally mint tokens to the deployer, e.g.:
        // _mint(msg.sender, 1_000_000 * 10**decimals());

        // By default, you can whitelist the owner:
        isWhitelisted[owner()] = true;
    }

    /**
     * @dev Owner can update the minimum snapshot interval.
     */
    function setMinInterval(uint256 newInterval) external onlyOwner {
        minInterval = newInterval;
    }

    /**
     * @dev Owner can add an address to the whitelist so it can call createSnapshot().
     */
    function addToWhitelist(address account) external onlyOwner {
        isWhitelisted[account] = true;
    }

    /**
     * @dev Owner can remove an address from the whitelist.
     */
    function removeFromWhitelist(address account) external onlyOwner {
        isWhitelisted[account] = false;
    }

    /**
     * @notice Creates a new snapshot, allocating `msg.value` ETH to it.
     *         Requires that `msg.sender` is whitelisted and must wait
     *         at least `minInterval` from the previous snapshot.
     */
    function createSnapshot() external payable {
        require(isWhitelisted[msg.sender], "Caller not whitelisted");
        require(
            block.timestamp >= lastSnapshotTime + minInterval,
            "Must wait longer for next snapshot"
        );

        lastSnapshotTime = block.timestamp;

        // Create a new snapshot using ERC20Snapshot's internal _snapshot().
        uint256 newSnapshotId = _snapshot();

        // Record how much ETH is allocated for this snapshot
        snapshotIdToEth[newSnapshotId] = msg.value;
    }

    /**
     * @notice Allows anyone to claim ETH for a token holder (owner) for a given snapshotId.
     *         The ETH goes to `owner`, not the caller, but the caller pays gas.
     * @param owner The token holder for whom to claim dividends.
     * @param snapshotId The snapshot ID being claimed.
     */
    function claim(address owner, uint256 snapshotId) external {
        require(!claimed[snapshotId][owner], "Already claimed");
        claimed[snapshotId][owner] = true;

        uint256 userBalance = balanceOfAt(owner, snapshotId);
        require(userBalance > 0, "No balance at snapshot");

        uint256 totalSupplyAtSnapshot = totalSupplyAt(snapshotId);
        require(totalSupplyAtSnapshot > 0, "No supply at snapshot");

        uint256 totalEthForSnapshot = snapshotIdToEth[snapshotId];
        require(totalEthForSnapshot > 0, "No ETH allocated");

        // Calculate the user's share
        uint256 amount = (totalEthForSnapshot * userBalance) /
            totalSupplyAtSnapshot;

        // Send ETH to the actual token holder
        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "ETH transfer failed");
    }
}
