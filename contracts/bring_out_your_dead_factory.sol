pragma solidity ^0.5.0;

import "bring_out_your_dead.sol";

contract BringOutYourDeadFactory {
    function newEstate(address oracle, address executor) public payable returns (address estateContract) {
        BringOutYourDead boyd = new BringOutYourDead();
        if(address(0) != oracle) {
            boyd.changeOracle(oracle);
        }
        if(address(0) != executor) {
            boyd.changeExecutor(executor);
        }
        boyd.transferOwnership(msg.sender);
        return address(boyd);
    }
}

