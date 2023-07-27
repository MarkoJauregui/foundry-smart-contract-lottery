// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployLottery} from "../../script/DeployLottery.s.sol";
import {Lottery} from "../../src/Lottery.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract LotteryTest is Test {
    // Events
    //-------------------------------------------------
    event EnteredLottery(address indexed player);

    Lottery lottery;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    modifier lotteryEnteredAndTimePassed() {
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function setUp() external {
        DeployLottery deployer = new DeployLottery();
        (lottery, helperConfig) = deployer.run();

        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link
        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testLotteryInitializesInOpenState() public view {
        assert(lottery.getLotteryState() == Lottery.LotteryState.OPEN);
    }

    ///////////////////
    // enterLottery
    ///////////////////
    function testLotteryRevertsWhenYouDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Lottery.Lottery__NotEnoughEthSent.selector);
        lottery.enterLottery();
    }

    function testLotteryStoresPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();
        assert(lottery.getPlayer(0) == PLAYER);
    }

    function testCantEnterWhenLotteryIsCalculating() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        lottery.performUpkeep("");

        vm.expectRevert(Lottery.Lottery__LotteryNotOpen.selector);
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(lottery));
        emit EnteredLottery(PLAYER);
        lottery.enterLottery{value: entranceFee}();
    }

    ///////////////////
    // checkUpkeep
    ///////////////////
    function testCheeckUpkeepIsFalseIfNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = lottery.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepIsFalseIfLotteryIsNotOpen()
        public
        lotteryEnteredAndTimePassed
    {
        // Arrange

        lottery.performUpkeep("");
        Lottery.LotteryState lotteryState = lottery.getLotteryState();
        // Act
        (bool upkeepNeeded, ) = lottery.checkUpkeep("");
        // Assert
        assert(lotteryState == Lottery.LotteryState.CALCULATING);
        assert(upkeepNeeded == false);
    }

    function testcheckUpkeepReturnsFalseIfEnoughTimeHasNotPassed() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();

        (bool upkeepNeeded, ) = lottery.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeeepReturnsTrueWhenParametersAreGood()
        public
        lotteryEnteredAndTimePassed
    {
        (bool upkeepNeeded, ) = lottery.checkUpkeep("");

        assert(upkeepNeeded);
    }

    ///////////////////
    // checkUpkeep
    ///////////////////

    function testPerformUpkeepOnlyRunIfCheckUpkeepIsTrue()
        public
        lotteryEnteredAndTimePassed
    {
        lottery.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 lotteryState = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                Lottery.Lottery__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                lotteryState
            )
        );
        lottery.performUpkeep("");
    }

    function testPerformUpkeepUpdatesLotteryStateAndEmitsRequestId()
        public
        lotteryEnteredAndTimePassed
    {
        vm.recordLogs();
        lottery.performUpkeep(""); // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Lottery.LotteryState lotState = lottery.getLotteryState();

        assert(uint256(requestId) > 0);
        assert(uint256(lotState) == 1); //CALCULATING
    }

    ///////////////////
    // fulfillRandomWords
    ///////////////////

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 requestRandomNumber
    ) public lotteryEnteredAndTimePassed {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            requestRandomNumber,
            address(lottery)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        lotteryEnteredAndTimePassed
    {
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i)); //address(i)
            hoax(player, STARTING_USER_BALANCE);
            lottery.enterLottery{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1);

        vm.recordLogs();
        lottery.performUpkeep(""); // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = lottery.getLastTimeStamp();

        // Pretend to be Chainlink VRF to get the random number & pick winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(lottery)
        );

        assert(uint256(lottery.getLotteryState()) == 0);
        assert(lottery.getRecentWinner() != address(0));
        assert(lottery.getLengthOfPlayersArray() == 0);
        assert(previousTimeStamp < lottery.getLastTimeStamp());
        assert(
            lottery.getRecentWinner().balance ==
                STARTING_USER_BALANCE + prize - entranceFee
        );
    }
}
