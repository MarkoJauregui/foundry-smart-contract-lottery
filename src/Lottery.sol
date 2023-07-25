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
    address payable[] private s_players;

    // Events
    //-------------------------------------------------
    event EnteredLottery(address indexed player);

    // Functions
    //-------------------------------------------------

    //constructor
    constructor(uint256 entranceFee) {
        i_entranceFee = entranceFee;
    }

    function enterLottery() external payable {
        // require(msg.value >= i_entranceFee, "NOT enough ETH sent");
        if (msg.value < i_entranceFee) {
            revert Lottery__NotEnoughEthSent();
        }
        s_players.push(payable(msg.sender));
        emit EnteredLottery(msg.sender);
    }

    function pickWinner() public {}

    // View/Pure Functions
    //-------------------------------------------------
    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }
}
