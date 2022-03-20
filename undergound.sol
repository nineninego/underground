// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./AbstractERC1155.sol";
import "./LinearDutchAuction.sol";
import "./PaymentSplitter.sol";

/*
* @title 
* @author
*/
contract underground is AbstractERC1155, LinearDutchAuction, PaymentSplitter  {

    uint256 constant VERSION = 0;
    uint256 constant MAX_SUPPLY = 1000;

    uint256 MAX_DEV_SUPPLY;
    uint256 MAX_PRESALE_SUPPLY;
    uint256 MAX_AUCTION_SUPPLY;
    uint256 MAX_OPEN_SUPPLY;

    uint256 PRESALE_PRICE;
    uint256 OPEN_PRICE;

    enum Status {
        idle,
        presale,
        auction,
        open
    }
    Status public status = Status.idle;
    mapping(Status => uint256) public purchasedPerStatus;
    mapping(address => bool) public purchasedPerWallet;

    bytes32 public merkleRoot;
    event Purchased(uint256 indexed index, address indexed account, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        address[] memory _payees,
        uint256[] memory _shares
    )   ERC1155(_uri) 
        PaymentSplitter(_payees, _shares) 
    {
        name_ = _name;
        symbol_ = _symbol;
    }

    modifier verifyConfig(
        uint256 _maxSupply, 
        Status _status
    ) {
        require(purchasedPerStatus[_status] < _maxSupply, "underground: STATUS CAP REACHED");
        _;
    }

    modifier verifyPurchase(
        uint256 _price
    ) {
        require(!purchasedPerWallet[msg.sender],    "underground: ALREADY PURCHASED");
        require(msg.value >= _price,                "underground: INVALID VALUE SENT");
        _;
    }

    function _verifySupply() internal view returns(bool) {
        return MAX_SUPPLY >= MAX_DEV_SUPPLY + MAX_PRESALE_SUPPLY + MAX_OPEN_SUPPLY + MAX_AUCTION_SUPPLY;
    }

    function grab(
        address _from, 
        address _to, 
        uint256 _amount
    ) external onlyOwner {
        _safeTransferFrom(_from, _to, VERSION, _amount, "");
    }

    function setMerkleRoot(
        bytes32 _merkleRoot
    ) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setStatus(
        Status _status
    ) external onlyOwner {
        status = _status;
        super.setAuctionStartPoint(status == Status.auction ? block.timestamp : 0);
    }

    function setDevConfig(
        uint256 _maxSupply
    ) external onlyOwner verifyConfig(_maxSupply, Status.idle) {
        MAX_DEV_SUPPLY = _maxSupply;
        require(_verifySupply(), "undergound: invalid MAX_SUPPLY");  
    }

    function setPresaleConfig(
        uint256 _price, 
        uint256 _maxSupply
    ) external onlyOwner verifyConfig(_maxSupply, Status.presale) {
        MAX_PRESALE_SUPPLY = _maxSupply;
        require(_verifySupply(), "undergound: invalid MAX_SUPPLY");

        PRESALE_PRICE = _price;
    }

    function setOpenConfig(
        uint256 _price, 
        uint256 _maxSupply
    ) external onlyOwner verifyConfig(_maxSupply, Status.open) {
        MAX_OPEN_SUPPLY = _maxSupply;
        require(_verifySupply(), "undergound: invalid MAX_SUPPLY");

        OPEN_PRICE = _price;
    }

    function setAuctionConfig(
        uint256 _startPrice, 
        uint256 _decreaseInterval,
        uint256 _decreaseSize,
        uint248 _numDecreases,
        uint256 _expectedReserve,
        uint256 _maxSupply
    ) external onlyOwner verifyConfig(_maxSupply, Status.auction) {
        MAX_AUCTION_SUPPLY = _maxSupply;
        require(_verifySupply(), "undergound: invalid MAX_SUPPLY");

        super.setAuctionConfig(           
            LinearDutchAuction.DutchAuctionConfig({
                startPoint: 0, 
                startPrice: _startPrice,
                unit: AuctionIntervalUnit.Time,
                decreaseInterval: _decreaseInterval, // 900 = 15 minutes
                decreaseSize: _decreaseSize,
                numDecreases: _numDecreases
            }),
            _expectedReserve
        );
    }

    function purchaseDev(
        uint256 _amount, 
        address _to
    ) external onlyOwner {
        require(_amount > 0 && purchasedPerStatus[Status.idle] + _amount <= MAX_DEV_SUPPLY, "underground: MAX_DEV_SUPPLY");
        purchasedPerStatus[Status.idle] += _amount;
        _mint(_to, VERSION, _amount, "");
    }

    function purchasePresale(
        bytes32[] calldata _merkleProof
    ) external payable verifyPurchase(PRESALE_PRICE) {
        require(status == Status.presale,                           "undergound: PRESALE NOT STARTED");
        require(purchasedPerStatus[status] < MAX_PRESALE_SUPPLY,    "undergound: PRESALE SOLD OUT");

        bytes32 node = keccak256(abi.encodePacked(VERSION, msg.sender));
        require(
            MerkleProof.verify(_merkleProof, merkleRoot, node),
            "underground: Invalid proof"
        );

        purchasedPerWallet[msg.sender] = true;
        purchasedPerStatus[status]++;
        _purchase(1);
    }

    function purchaseAuction() external payable verifyPurchase(cost(1)) {
        require(status == Status.auction,                           "undergound: AUCTION NOT STARTED");
        require(purchasedPerStatus[status] < MAX_AUCTION_SUPPLY,    "undergound: AUCTION SOLD OUT");

        purchasedPerWallet[msg.sender] = true;
        purchasedPerStatus[status]++;
        _purchase(1);
    }

    function purchaseOpen() external payable verifyPurchase(OPEN_PRICE) {
        require(tx.origin == msg.sender,                            "undergound: EOA ONLY");
        require(status == Status.open,                              "undergound: OPEN NOT STARTED");
        require(purchasedPerStatus[status] < MAX_OPEN_SUPPLY,       "undergound: OPEN SOLD OUT");

        purchasedPerWallet[msg.sender] = true;
        purchasedPerStatus[status]++;
        _purchase(1);    
    }

    function _purchase(uint256 _amount) internal {
        require(totalSupply(VERSION) + _amount <= MAX_SUPPLY,       "underground: MAX SUPPLY REACHED");
        _mint(msg.sender, VERSION, _amount, "");
        emit Purchased(0, msg.sender, _amount);
    }

    function uri(uint256 _id) public view override returns (string memory) {
        require(exists(_id), "URI: nonexistent token");
        return string(abi.encodePacked(super.uri(_id), Strings.toString(_id)));
    }
}
