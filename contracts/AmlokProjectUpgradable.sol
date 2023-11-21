// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "hardhat/console.sol";
import "./IERC2981Royalties.sol";

contract AmlokProjectUpgradable is Initializable, ERC721Upgradeable, ERC721URIStorageUpgradeable,
ERC721EnumerableUpgradeable, OwnableUpgradeable, ERC721Holder, ERC721BurnableUpgradeable, ReentrancyGuard {

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;
    Counters.Counter private _distributionCounter;

    Status private _status;

    address private _royaltyReceiver;
    string[] private _tokenTypesUri;
    string private _contractUri;
    uint256[] private _tokenTypeQty;
    uint256 private _price;
    uint256 private _maxQty;
    uint256 private _totalSell;
    uint256 private _cancelTime;

    //tokenId->true if no re found
    mapping(uint256 => bool) private _tokenNoReFound;
    //tokenId->qty
    mapping(uint256 => uint256) private _tokenQty;
    //distributionId->eth amount
    mapping(uint256 => uint256) private _distributionValues;
    //distributionId->tokenId->claimed
    mapping(uint256 => mapping(uint256 => bool)) private _distributionTokenClaimed;

    enum Status {
        NEW,
        GOAL_REACHED,
        ACTIVE,
        CANCELED
    }

    event Document(string documentUri);
    event SetCancelTime(uint256 time);
    event ManualTransfer(address to);

    function initialize(string memory contractUri, string memory name, string memory symbol,
        string[] memory tokenTypesUri, uint256[] memory tokenTypesQty, uint256 price, uint256 maxQty, 
        uint256 cancelTime, address owner, address royaltyReceiver) initializer public {
        __ERC721_init_unchained(name, symbol);
        _transferOwnership(owner);

        _royaltyReceiver = royaltyReceiver;
        _tokenTypesUri = tokenTypesUri;
        _tokenTypeQty = tokenTypesQty;
        _contractUri = contractUri;
        _price = price;
        _maxQty = maxQty;
        require(_tokenTypesUri.length == _tokenTypeQty.length, "constructor: wrong token types count");
        _status = Status.NEW;
        _cancelTime = cancelTime;
        emit Document(_contractUri);
        emit SetCancelTime(_cancelTime);
    }

    function buy(uint[] memory tokenTypes) payable nonReentrant external {
        require(getStatus() == Status.NEW, "buy: allow only for status new");
        uint256 paymentRequire = 0;
        for (uint256 i = 0; i < tokenTypes.length; i++) {

            _tokenIdCounter.increment();
            uint256 tokenId = _tokenIdCounter.current();
            _mint(msg.sender, tokenId);
            uint256 tokenTypeIndex = tokenTypes[i];
            require(tokenTypeIndex < _tokenTypesUri.length, "wrong token type");
            _setTokenURI(tokenId, _tokenTypesUri[tokenTypeIndex]);
            _tokenQty[tokenId] = _tokenTypeQty[tokenTypeIndex];
            paymentRequire += _tokenTypeQty[tokenTypeIndex] * _price;
            _totalSell += _tokenTypeQty[tokenTypeIndex];
        }
        require(_totalSell <= _maxQty, "buy: buy more then limit");
        require(msg.value == paymentRequire, "buy: wrong payment value");
    }

    function reFound() nonReentrant external {
        require(getStatus() == Status.CANCELED, "reFound: only for cancel status");
        uint256 balance = ERC721Upgradeable.balanceOf(msg.sender);
        uint256 reFoundAmount = 0;
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(msg.sender, 0);
            transferFrom(msg.sender, address(this), tokenId);
            if (!_tokenNoReFound[tokenId])
                reFoundAmount += _tokenQty[tokenId] * _price;
        }
        if (reFoundAmount > 0)
            payable(msg.sender).transfer(reFoundAmount);
    }

    function claimDistribution(uint256 distributionId) nonReentrant external {
        require(distributionId < _distributionCounter.current(), "distribution should be less then current");
        uint256 balance = ERC721Upgradeable.balanceOf(msg.sender);
        
        uint256 notClaimedTokens = 0;
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(msg.sender, i);
            if (_distributionTokenClaimed[distributionId][tokenId])
                continue;

            _distributionTokenClaimed[distributionId][tokenId] = true;

            notClaimedTokens += _tokenQty[tokenId];
        }

        uint256 totalAmount = _distributionValues[distributionId];
        payable(msg.sender).transfer(totalAmount * notClaimedTokens / _totalSell);
    }


    //===============================Only owner=================================

    //todo: is only owner?
    function createDistribution(string memory documentUri) external onlyOwner payable {
        uint256 distributionId = _distributionCounter.current();
        _distributionValues[distributionId] = msg.value;
        _distributionCounter.increment();
        emit Document(documentUri);
    }

    function withdrawal(string memory documentUri) external onlyOwner {
        Status currentStatus = getStatus();
        require(currentStatus == Status.NEW || currentStatus == Status.GOAL_REACHED, "withdrawal:only for status new or goal reached");

        payable(msg.sender).transfer(address(this).balance);
        _status = Status.ACTIVE;
        emit Document(documentUri);
    }

    function manualTransfer(uint[] memory tokenTypes, address to, string memory documentUri) external onlyOwner {
        require(getStatus() == Status.NEW, "manualTransfer: allow only for status new");
        for (uint256 i = 0; i < tokenTypes.length; i++) {

            _tokenIdCounter.increment();
            uint256 tokenId = _tokenIdCounter.current();
            _mint(to, tokenId);
            uint256 tokenTypeIndex = tokenTypes[i];
            require(tokenTypeIndex < _tokenTypesUri.length, "wrong token type");
            _setTokenURI(tokenId, _tokenTypesUri[tokenTypeIndex]);
            _tokenQty[tokenId] = _tokenTypeQty[tokenTypeIndex];
            _tokenNoReFound[tokenId] = true;
            _totalSell += _tokenTypeQty[tokenTypeIndex];
        }
        require(_totalSell <= _maxQty, "manualTransfer: transfer more then limit");
        emit ManualTransfer(to);
        emit Document(documentUri);
    }

    function cancel(string memory documentUri) external onlyOwner {
        _status = Status.CANCELED;
        emit Document(documentUri);
    }

    function setCancelTime(uint256 cancelTime, string memory documentUri) external onlyOwner {
        require(getStatus() != Status.CANCELED, "setCancelTime: status should not be canceled");
        require(_cancelTime < cancelTime, "setCancelTime: new time should be more then prev");
        _cancelTime = cancelTime;
        emit SetCancelTime(_cancelTime);
        emit Document(documentUri);
    }

    //===============================Views=================================

    function calculateDistributionAmount(uint256 distributionId, address user) external view returns (uint256){
        uint256 balance = ERC721Upgradeable.balanceOf(user);

        uint256 notClaimedTokens = 0;
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(user, i);
            if (_distributionTokenClaimed[distributionId][tokenId])
                continue;

            notClaimedTokens += _tokenQty[tokenId];
        }
        uint256 totalAmount = _distributionValues[distributionId];

        return totalAmount * notClaimedTokens / _totalSell;
    }

    function getStatus() public view returns (Status){
        if (_status == Status.NEW && _totalSell == _maxQty)
            return Status.GOAL_REACHED;

        if (_status == Status.NEW && _cancelTime < block.timestamp)
            return Status.CANCELED;


        return _status;
    }

    function royaltyInfo(uint256, uint256 value)
    external
    view
    returns (address receiver, uint256 royaltyAmount)
    {
        receiver = _royaltyReceiver;
        royaltyAmount = (value * 3000) / 10000;  //30%
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

    function getPrice() public view returns (uint256) {
        return _price;
    }

    function getTotalBuy() public view returns (uint256) {
        return _totalSell;
    }

    function getCancelTime() public view returns (uint256) {
        return _cancelTime;
    }

    function getMaxQty() public view returns (uint256) {
        return _maxQty;
    }

    function getTokenTypeCount() external view virtual returns (uint256) {
        return _tokenTypesUri.length;
    }

    function getTokenTypeUri(uint256 index) external view virtual returns (string memory) {
        return _tokenTypesUri[index];
    }

    function getTokenTypQty(uint256 index) external view virtual returns (uint256) {
        return _tokenTypeQty[index];
    }

    function getQtyByTokenId(uint256 tokenId) external view virtual returns (uint256) {
        return _tokenQty[tokenId];
    }

    //===============================erc721=================================
    
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

    function _burn(uint256 tokenId) internal virtual override (ERC721URIStorageUpgradeable, ERC721Upgradeable) {
        ERC721URIStorageUpgradeable._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view virtual override(ERC721URIStorageUpgradeable, ERC721Upgradeable) returns (string memory) {
        return ERC721URIStorageUpgradeable.tokenURI(tokenId);
    }
}
