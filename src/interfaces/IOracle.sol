// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/types/ClankerWarsTypes.sol";

/**
 * @title IOracle
 * @notice Interface for battle resolution oracle
 */
interface IOracle {
    /**
     * @notice Request battle resolution from oracle
     * @param battleId The battle to resolve
     * @param agentA First agent address
     * @param agentB Second agent address
     * @param market Market being traded
     * @param startTime Battle start timestamp
     * @param endTime Battle end timestamp
     */
    function requestResolution(
        uint256 battleId,
        address agentA,
        address agentB,
        address market,
        uint256 startTime,
        uint256 endTime
    ) external;

    /**
     * @notice Get resolution for a battle
     * @param battleId The battle ID
     * @return winner The winning agent address (zero if not resolved)
     * @return resolutionData Additional resolution data
     * @return resolved Whether the battle is resolved
     */
    function getResolution(uint256 battleId)
        external
        view
        returns (address winner, bytes32 resolutionData, bool resolved);

    /**
     * @notice Callback for oracle to report resolution
     * @param battleId The battle ID
     * @param winner The winning agent address
     * @param resolutionData Additional resolution data
     */
    function reportResolution(
        uint256 battleId,
        address winner,
        bytes32 resolutionData
    ) external;
}
