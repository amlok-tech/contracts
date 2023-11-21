// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./AmlokProjectUpgradable.sol";

contract AmlokProjectFactory {

    address public immutable AmlokProjectImplementation;
    address private _royaltyReceiver;

    //===== Events =====//
    event CreateAmlokProject(
        address projectAddress,
        address owner
    );

    //===== Constructor =====//
    constructor(address royaltyReceiver) {
        _royaltyReceiver = royaltyReceiver;
        AmlokProjectImplementation = address(new AmlokProjectUpgradable());
    }

    //===== External Functions =====//
    function createProject(
        string memory contractUri, string memory name, string memory symbol,
        string[] memory tokenTypesUri, uint256[] memory tokenTypesQty, uint256 price, 
        uint256 maxQty, uint256 cancelTime
    ) external returns (address) {
        address clone = Clones.clone(AmlokProjectImplementation);
        AmlokProjectUpgradable(clone).initialize(contractUri, name, symbol,
            tokenTypesUri, tokenTypesQty, price, maxQty, cancelTime, msg.sender, _royaltyReceiver);
        emit CreateAmlokProject(clone, msg.sender);
        return clone;
    }
}
