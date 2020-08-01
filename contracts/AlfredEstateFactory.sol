pragma solidity ^0.6.0;

// Alfred.Estate - Proof of Death - Digital Inheritance Automation

import "./AlfredEstate.sol";

contract BringOutYourDeadFactory {
    event estateCreated(address indexed estate, address indexed owner);

    // Use CREATE2 to create estate at predeterminable address
    function newEstate(address oracle, address executor, uint256 salt) public payable returns (address payable estate) {
        bytes memory code = type(BringOutYourDead).creationCode;
        bytes32 newsalt = keccak256(abi.encodePacked(salt, msg.sender));
        // address salt = msg.sender;
        assembly {
            estate := create2(0, add(code, 0x20), mload(code), newsalt)
            if iszero(extcodesize(estate)) { revert(0, 0) }
        }
        if(address(0) != oracle) {
            BringOutYourDead(estate).changeOracle(oracle);
        }
        if(address(0) != executor) {
            BringOutYourDead(estate).changeExecutor(executor);
        }
        BringOutYourDead(estate).transferOwnership(msg.sender);
        emit estateCreated(address(estate), msg.sender);
    }

    function getEstateAddress(address creator, uint256 salt) public view returns (address estate) {
        bytes memory code = type(BringOutYourDead).creationCode;
        bytes32 newsalt = keccak256(abi.encodePacked(salt, creator));
        bytes memory packed_bytecode = abi.encodePacked(code);
        bytes32 temp = keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(newsalt), bytes32(keccak256(packed_bytecode))));
        uint mask = 2 ** 160 - 1;
        assembly {
            estate := and(temp, mask)
        }
        return estate;

    }

    // Old approach, using original CREATE rather than CREATE2
/*
    function newEstate(address oracle, address executor) public payable returns (address estateContract) {
        BringOutYourDead boyd = new BringOutYourDead();
        if(address(0) != oracle) {
            boyd.changeOracle(oracle);
        }
        if(address(0) != executor) {
            boyd.changeExecutor(executor);
        }
        boyd.transferOwnership(msg.sender);
        emit estateCreated(address(boyd), msg.sender);
        return address(boyd);
    }
*/

}
