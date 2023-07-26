// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// Import Statements
//-------------------------------------------------
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title Lottery
 * @author Marko Jauregui
 * @notice This contract is to create a sample smart contract for personal learning of the Foundry framework
 * @dev Implements Chainlink VRFv2
 */

contract Lottery is VRFConsumerBaseV2 {
    // Custom Errors
    //-------------------------------------------------
    error Lottery__NotEnoughEthSent();
    error Lottery__NotEnoughTimePassed();
    error Lottery__TransferFailed();
    error Lottery__LotteryNotOpen();
    error Lottery__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 lotteryState
    );

    // Type Declarations
    //-------------------------------------------------
    enum LotteryState {
        OPEN, // 0
        CALCULATING // 1
    }

    // Variables
    //-------------------------------------------------

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    /// @dev interval: Duration of the lottery in seconds
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subcsriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    LotteryState private s_lotteryState;

    // Events
    //-------------------------------------------------
    event EnteredLottery(address indexed player);
    event PickedWinner(address indexed winner);

    // Functions
    //-------------------------------------------------

    //constructor
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subcsriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lotteryState = LotteryState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterLottery() external payable {
        // require(msg.value >= i_entranceFee, "NOT enough ETH sent");
        if (msg.value < i_entranceFee) {
            revert Lottery__NotEnoughEthSent();
        }
        if (s_lotteryState != LotteryState.OPEN)
            revert Lottery__LotteryNotOpen();
        s_players.push(payable(msg.sender));
        emit EnteredLottery(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink Keeper nodes call
     * they look for `upkeepNeeded` to return True.
     * the following should be true for this to return true:
     * 1. The time interval has passed between lottery runs.
     * 2. The lottery is open.
     * 3. The contract has ETH.
     * 4. Implicity, your subscription is funded with LINK.
     */
    function checkUpkeep(
        bytes memory /*checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory /*performData*/) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = LotteryState.OPEN == s_lotteryState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        //check if enough time has passed
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Lottery__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_lotteryState)
            );
        }
        if ((block.timestamp - s_lastTimeStamp) < i_interval) {
            revert Lottery__NotEnoughTimePassed();
        }
        s_lotteryState = LotteryState.CALCULATING;
        i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subcsriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
    }

    function fulfillRandomWords(
        uint256 /*requestId */,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_lotteryState = LotteryState.OPEN;

        /// @dev Here we reset the players Array and timestamp to make sure we don't try to re-enter the same contract
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(s_recentWinner);

        (bool success, ) = s_recentWinner.call{value: address(this).balance}(
            ""
        );
        if (!success) revert Lottery__TransferFailed();
    }

    // View/Pure Functions
    //-------------------------------------------------
    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getLotteryState() external view returns (LotteryState) {
        return s_lotteryState;
    }

    function getPlayer(uint256 playerIndex) external view returns (address) {
        return s_players[playerIndex];
    }
}
