// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./AmlokProjectTokenUpgradable.sol";
import "hardhat/console.sol";

contract AmlokProjectTokenFactory {

    address public immutable AmlokProjectImplementation;
    address private _royaltyReceiver;
    mapping(address => bool) private _projects;

    enum InvestorActionType {
        Buy,
        ReFound,
        Claim
    }

    //===== Events =====//
    event CreateAmlokProject(uint projectId, address projectAddress, address owner);
    event ProjectChangeStatus(address project, AmlokProjectTokenUpgradable.Status newStatus, string document);
    event InvestorAction(address project, address investor, InvestorActionType actionType, uint amount);
    event ManualTransfer(address project, address investor, uint amount, string document);
    event CreateDistribution(address project, uint256 amount, uint256 distributionId, string document);
    event SetDeadline(address project, uint256 time, string document);
    event UserTransfer(address project, address from, address to, uint256 tokenId);
    event ClaimDistribution(address project, address investor, uint256[] distributions);

    //===== Constructor =====//
    constructor(address royaltyReceiver) {
        _royaltyReceiver = royaltyReceiver;
        AmlokProjectImplementation = address(new AmlokProjectTokenUpgradable());
    }

    //===== External Functions =====//
    function createProject(
        uint projectId,
        string memory contractUri, string memory name, string memory symbol,
        string memory tendersBaseUri, uint256[] memory tokenTypesQty, IERC20 token, 
        uint256 maxGoal, uint256 deadline
    ) external returns (address) {
        address clone = Clones.clone(AmlokProjectImplementation);
        _projects[clone] = true;
        AmlokProjectTokenUpgradable(clone).initialize(contractUri, name, symbol,
            tendersBaseUri, tokenTypesQty, token, maxGoal, deadline, msg.sender, _royaltyReceiver, this);
        emit CreateAmlokProject(projectId, clone, msg.sender);
        return clone;
    }


    //===== Notifications =====//

    modifier onlyProject() {
        require(_projects[msg.sender], 'onlyProject: only for projects');
        _;
    }

    function changeStatus(AmlokProjectTokenUpgradable.Status newStatus, string memory document) onlyProject public {
        emit ProjectChangeStatus(msg.sender, newStatus, document);
    }

    function investorAction(address investor, InvestorActionType actionType, uint amount) onlyProject public {
        emit InvestorAction(msg.sender, investor, actionType, amount);
    }

    function manualTransfer(address investor, uint amount, string memory document) onlyProject public {
        emit ManualTransfer(msg.sender, investor, amount, document);
    }

    function createDistribution(uint amount, uint256 distributionId, string memory document) onlyProject public {
        emit CreateDistribution(msg.sender, amount, distributionId, document);
    }

    function setDeadline(uint time, string memory document) onlyProject public {
        emit SetDeadline(msg.sender, time, document);
    }

    function userTransfer(address from, address to, uint256 tokenId) onlyProject public {
        emit UserTransfer(msg.sender, from, to, tokenId);
    }

    function claimDistribution(address investor, uint256[] memory distributions) onlyProject public {
        emit ClaimDistribution(msg.sender, investor, distributions);
    }
}
