// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// Import Statements
//-------------------------------------------------

// Custom Errors
//-------------------------------------------------
error Lottery__NotEnoughEthSent();

/**
 * @title Lottery
 * @author Marko Jauregui
 * @notice This contract is to create a sample smart contract for personal learning of the Foundry framework
 * @dev Implements Chainlink VRFv2
 */

contract Lottery {
    // Variables
    //-------------------------------------------------
    uint256 private immutable i_entranceFee;

    // Functions
    //-------------------------------------------------
    constructor(uint256 entranceFee) {
        i_entranceFee = entranceFee;
    }

    function enterLottery() external payable {
        // require(msg.value >= i_entranceFee, "NOT enough ETH sent");
        if (msg.value < i_entranceFee) {
            revert Lottery__NotEnoughEthSent();
        }
    }

    function pickWinner() public {}

    // View/Pure Functions
    //-------------------------------------------------
    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }
}
