// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";
import "./IERC2981Royalties.sol";
import "./AmlokProjectTokenFactory.sol";


contract AmlokProjectTokenUpgradable is Initializable, ERC721Upgradeable,
ERC721EnumerableUpgradeable, OwnableUpgradeable, ERC721Holder, ERC721BurnableUpgradeable, ReentrancyGuard {

    using StringsUpgradeable for uint256;
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;
    Counters.Counter private _distributionCounter;
    AmlokProjectTokenFactory private _factory;

    Status private _status;

    address private _royaltyReceiver;
    IERC20 private _token;
    string private _tendersBaseUri;
    string private _contractUri;
    uint256[] private _tokenTypeQty;
    uint256 private _maxGoal;
    uint256 private _totalRaised;
    uint256 private _deadline;

    //tokenId->true if no re found
    mapping(uint256 => bool) private _tokenNoReFound;
    //tokenId->typeId
    mapping(uint256 => uint256) private _tokenType;
    //distributionId->eth amount
    mapping(uint256 => uint256) private _distributionValues;
    //distributionId->tokenId->claimed
    mapping(uint256 => mapping(uint256 => bool)) private _distributionTokenClaimed;

    enum Status {
        NEW, //0
        GOAL_REACHED, //1
        ACTIVE, //2
        CANCELED//3
    }

    function initialize(string memory contractUri, string memory name, string memory symbol,
        string memory tendersBaseUri, uint256[] memory tokenTypesQty, IERC20 token, uint256 maxGoal,
        uint256 deadline, address owner, address royaltyReceiver, AmlokProjectTokenFactory factory) initializer public {
        __ERC721_init_unchained(name, symbol);
        _transferOwnership(owner);
        _factory = factory;
        _token = token;
        _royaltyReceiver = royaltyReceiver;
        _tendersBaseUri = tendersBaseUri;
        _tokenTypeQty = tokenTypesQty;
        _contractUri = contractUri;
        _maxGoal = maxGoal;
        _status = Status.NEW;
        _deadline = deadline;
        _factory.setDeadline(_deadline, "");
    }

    function buy(uint[] memory tokenTypes) nonReentrant external {
        require(getStatus() == Status.NEW, "buy: allow only for status new");
        uint256 paymentRequire = 0;
        uint sold = 0;
        for (uint256 i = 0; i < tokenTypes.length; i++) {

            _tokenIdCounter.increment();
            uint256 tokenId = _tokenIdCounter.current();
            _mint(msg.sender, tokenId);
            uint256 tokenTypeIndex = tokenTypes[i];
            _tokenType[tokenId] = tokenTypeIndex;
            paymentRequire += _tokenTypeQty[tokenTypeIndex];
            sold += _tokenTypeQty[tokenTypeIndex];
        }
        _totalRaised += sold;
        require(_totalRaised <= _maxGoal, "buy: buy more then limit");
        _token.safeTransferFrom(msg.sender, address(this), paymentRequire);
        _factory.investorAction(msg.sender, AmlokProjectTokenFactory.InvestorActionType.Buy, sold);
        if (_totalRaised == _maxGoal) {
            _factory.changeStatus(Status.GOAL_REACHED, "");
        }
    }

    function reFound() nonReentrant external {
        require(getStatus() == Status.CANCELED, "reFound: only for cancel status");
        uint256 balance = ERC721Upgradeable.balanceOf(msg.sender);
        uint256 reFoundAmount = 0;
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(msg.sender, 0);
            transferFrom(msg.sender, address(this), tokenId);
            if (!_tokenNoReFound[tokenId])
                reFoundAmount += getQtyByTokenId(tokenId);
        }
        if (reFoundAmount > 0) {
            _token.safeTransfer(msg.sender, reFoundAmount);
            _factory.investorAction(msg.sender, AmlokProjectTokenFactory.InvestorActionType.ReFound, reFoundAmount);
        }
    }

    function claimDistributions(uint256[] memory distributions) nonReentrant external {

        uint256 balance = ERC721Upgradeable.balanceOf(msg.sender);
        //todo: possible claim future distributions
        uint256 notClaimedTokens = 0;
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(msg.sender, i);

            for (uint256 j = 0; j < distributions.length; j++) {
                uint256 distributionId = distributions[j];
                
                //todo: should be fail
                if(distributionId >= _distributionCounter.current())
                    continue;
                if (_distributionTokenClaimed[distributionId][tokenId])
                    continue;

                _distributionTokenClaimed[distributionId][tokenId] = true;

                notClaimedTokens += getQtyByTokenId(tokenId);
            }
        }

        uint256 totalAmount = 0;
        for (uint256 j = 0; j < distributions.length; j++) {
            uint256 distributionId = distributions[j];
            totalAmount += _distributionValues[distributionId];
        }

        //todo: wrong  formula!!!!!!!! security issue
        uint256 claimedAmount = totalAmount * notClaimedTokens / _totalRaised;
        _token.safeTransfer(msg.sender, claimedAmount);
        //todo: remove events
        _factory.investorAction(msg.sender, AmlokProjectTokenFactory.InvestorActionType.Claim, claimedAmount);
        _factory.claimDistribution(msg.sender, distributions);
    }

    //===============================Only owner=================================

    function createDistribution(uint256 amount, string memory documentUri) external onlyOwner {
        Status currentStatus = getStatus();
        require(currentStatus != Status.CANCELED && currentStatus != Status.NEW, "createDistribution: wrong status");
        _token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 distributionId = _distributionCounter.current();
        _distributionValues[distributionId] = amount;
        _distributionCounter.increment();
        _factory.createDistribution(amount, distributionId, documentUri);
    }

    function withdrawal(string memory documentUri) external onlyOwner {
        Status currentStatus = getStatus();
        require(currentStatus == Status.NEW || currentStatus == Status.GOAL_REACHED, "withdrawal:only for status new or goal reached");

        _token.safeTransfer(msg.sender, _token.balanceOf(address(this)));

        _status = Status.ACTIVE;
        _factory.changeStatus(_status, documentUri);
    }

    function manualTransfer(uint[] memory tokenTypes, address to, string memory documentUri) external onlyOwner {
        require(getStatus() == Status.NEW, "manualTransfer: allow only for status new");
        uint256 sold = 0;
        for (uint256 i = 0; i < tokenTypes.length; i++) {

            _tokenIdCounter.increment();
            uint256 tokenId = _tokenIdCounter.current();
            _mint(to, tokenId);
            uint256 tokenTypeIndex = tokenTypes[i];
            _tokenType[tokenId] = tokenTypeIndex;
            _tokenNoReFound[tokenId] = true;
            sold += _tokenTypeQty[tokenTypeIndex];
        }
        _totalRaised += sold;
        require(_totalRaised <= _maxGoal, "manualTransfer: transfer more then limit");
        _factory.investorAction(to, AmlokProjectTokenFactory.InvestorActionType.Buy, sold);
        _factory.manualTransfer(to, sold, documentUri);
    }

    function cancel(string memory documentUri) external onlyOwner {
        _status = Status.CANCELED;
        _factory.changeStatus(_status, documentUri);
    }

    function setDeadline(uint256 deadline, string memory documentUri) external onlyOwner {
        require(getStatus() != Status.CANCELED, "setCancelTime: status should not be canceled");
        require(_deadline < deadline, "setCancelTime: new time should be more then prev");
        _deadline = deadline;
        _factory.setDeadline(_deadline, documentUri);
    }

    //===============================Views=================================

    function calculateDistributionAmount(uint256 distributionId, address user) external view returns (uint256){
        uint256 balance = ERC721Upgradeable.balanceOf(user);

        uint256 notClaimedTokens = 0;
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(user, i);
            if (_distributionTokenClaimed[distributionId][tokenId])
                continue;

            notClaimedTokens += getQtyByTokenId(tokenId);
        }
        uint256 totalAmount = _distributionValues[distributionId];

        return totalAmount * notClaimedTokens / _totalRaised;
    }

    function getStatus() public view returns (Status){
        if (_status == Status.NEW && _totalRaised == _maxGoal)
            return Status.GOAL_REACHED;

        if (_status == Status.NEW && _deadline < block.timestamp)
            return Status.CANCELED;

        return _status;
    }

    function royaltyInfo(uint256, uint256 value)
    external
    view
    returns (address receiver, uint256 royaltyAmount)
    {
        receiver = _royaltyReceiver;
        //30%
        royaltyAmount = (value * 3000) / 10000;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        return string(abi.encodePacked(_tendersBaseUri,'/', getQtyByTokenId(tokenId).toString(), '.json'));
    }

    function getQtyByTokenId(uint256 tokenId) public view virtual returns (uint256) {
        return _tokenTypeQty[_tokenType[tokenId]];
    }

    function isClaimed(uint256 distributionId, uint256 tokenId) public view returns (bool){
        return _distributionTokenClaimed[distributionId][tokenId];
    }

    function getTotalDistributions() public view returns (uint256){
        return _distributionCounter.current();
    }

    function contractURI() public view returns (string memory) {
        return _contractUri;
    }

    function getTotalRaised() public view returns (uint256) {
        return _totalRaised;
    }

    function getCancelTime() public view returns (uint256) {
        return _deadline;
    }

    function getMaxQty() public view returns (uint256) {
        return _maxGoal;
    }

    function getTokenTypeCount() external view virtual returns (uint256) {
        return _tokenTypeQty.length;
    }

    function getTendersBaseUri() external view virtual returns (string memory) {
        return _tendersBaseUri;
    }

    function getTokenTypQty(uint256 index) external view virtual returns (uint256) {
        return _tokenTypeQty[index];
    }

    function getToken() external view virtual returns (address){
        return address(_token);
    }

    //===============================erc721=================================

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        _factory.userTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    returns (bool)
    {
        return interfaceId == type(IERC2981Royalties).interfaceId ||
        ERC721EnumerableUpgradeable.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        ERC721EnumerableUpgradeable._beforeTokenTransfer(from, to, tokenId);
    }
}
