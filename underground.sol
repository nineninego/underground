// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./AbstractERC1155.sol";
import "./LinearDutchAuction.sol";

/*
* @title 
* @author
*/
contract underground is AbstractERC1155, LinearDutchAuction {

    uint256 constant VERSION = 0;
    uint256 constant public MAX_SUPPLY = 785;

    uint256 public MAX_DEV_SUPPLY;
    uint256 public MAX_PRESALE_SUPPLY;
    uint256 public MAX_AUCTION_SUPPLY;
    uint256 public MAX_OPEN_SUPPLY;

    uint256 public PRESALE_PRICE;
    uint256 public OPEN_PRICE;

    enum Status {
        idle,
        presale,
        auction,
        open
    }
    Status public status = Status.idle;
    mapping(address => bool) public purchasedPerWallet;
    mapping(Status => uint256) public purchasedPerStatus;

    address public recipient;
    bytes32 public merkleRoot;
    mapping(address => bool) public isAdmin;
    event Purchased(uint256 indexed index, address indexed account, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        address _recipient
    )   ERC1155(_uri) 
    {
        name_ = _name;
        symbol_ = _symbol;
        recipient = _recipient;
    }

    modifier onlyAdmin() {
        require(isAdmin[msg.sender] || msg.sender == owner(), "underground: only admin");
        _;
    }

    modifier verifyConfig(
        uint256 _maxSupply, 
        Status _status
    ) {
        require(purchasedPerStatus[_status] <= _maxSupply, "underground: status cap reached");
        _;
    }

    modifier verifyPurchase(
        uint256 _price
    ) {
        require(!purchasedPerWallet[msg.sender],    "underground: already purchased");
        require(msg.value >= _price,                "underground: invalid value sent");
        _;
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
    ) external onlyAdmin {
        merkleRoot = _merkleRoot;
    }

    function setStatus(
        Status _status
    ) external onlyAdmin  {
        status = _status;
        super.setAuctionStartPoint(status == Status.auction ? block.timestamp : 0);
    }

    function setDevConfig(
        uint256 _maxSupply
    ) external onlyAdmin verifyConfig(_maxSupply, Status.idle) {
        MAX_DEV_SUPPLY = _maxSupply;
        require(_verifySupply(), "underground: invalid MAX_SUPPLY");  
    }

    function setPresaleConfig(
        uint256 _price, 
        uint256 _maxSupply
    ) external onlyAdmin verifyConfig(_maxSupply, Status.presale) {
        MAX_PRESALE_SUPPLY = _maxSupply;
        require(_verifySupply(), "underground: invalid MAX_SUPPLY");

        PRESALE_PRICE = _price;
    }

    function setOpenConfig(
        uint256 _price, 
        uint256 _maxSupply
    ) external onlyAdmin verifyConfig(_maxSupply, Status.open) {
        MAX_OPEN_SUPPLY = _maxSupply;
        require(_verifySupply(), "underground: invalid MAX_SUPPLY");

        OPEN_PRICE = _price;
    }

    function setAuctionConfig(
        uint256 _startPrice, 
        uint256 _decreaseInterval,
        uint256 _decreaseSize,
        uint248 _numDecreases,
        uint256 _expectedReserve,
        uint256 _maxSupply
    ) external onlyAdmin verifyConfig(_maxSupply, Status.auction) {
        MAX_AUCTION_SUPPLY = _maxSupply;
        require(_verifySupply(), "underground: invalid MAX_SUPPLY");

        super.setAuctionConfig(           
            LinearDutchAuction.DutchAuctionConfig({
                startPoint: 0, 
                startPrice: _startPrice,
                unit: AuctionIntervalUnit.Time,
                decreaseInterval: _decreaseInterval, // 60 = 1 minute
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
        require(status == Status.presale,                           "underground: presale not started");
        require(purchasedPerStatus[status] < MAX_PRESALE_SUPPLY,    "underground: presale sold out");

        bytes32 node = keccak256(abi.encodePacked(VERSION, msg.sender));
        require(
            MerkleProof.verify(_merkleProof, merkleRoot, node),
            "underground: invalid proof"
        );

        purchasedPerWallet[msg.sender] = true;
        purchasedPerStatus[status]++;
        _purchase(1);
    }

    function purchaseAuction() external payable verifyPurchase(cost(1)) {
        require(tx.origin == msg.sender,                                        "underground: eoa only");
        require(status == Status.auction && dutchAuctionConfig.startPoint != 0, "underground: auction not started");
        require(purchasedPerStatus[status] < MAX_AUCTION_SUPPLY,                "underground: auction sold out");

        purchasedPerWallet[msg.sender] = true;
        purchasedPerStatus[status]++;
        _purchase(1);
    }

    function purchaseOpen() external payable verifyPurchase(OPEN_PRICE) {
        require(tx.origin == msg.sender,                        "underground: eoa only");
        require(status == Status.open,                          "underground: open not started");
        require(purchasedPerStatus[status] < MAX_OPEN_SUPPLY,   "underground: open sold out");

        purchasedPerWallet[msg.sender] = true;
        purchasedPerStatus[status]++;
        _purchase(1);    
    }

    function uri(
        uint256 _id
    ) public view override returns (string memory) {
        require(exists(_id), "URI: nonexistent token");
        return string(abi.encodePacked(super.uri(_id), Strings.toString(_id)));
    }

    function changeRecipient(
        address _recipient
    ) external onlyOwner {
        recipient = _recipient;
    }

    function addAdmin(
        address[] calldata _admins
    ) external onlyOwner {
        uint256 l = _admins.length;
        for(uint256 i = 0; i < l; i++) {
            isAdmin[_admins[i]] = true;
        }
    }

    function removeAdmin(
        address _admin
    ) external onlyOwner {
        isAdmin[_admin] = false;
    }

    function withdraw() external onlyOwner {
        recipient.call{value: address(this).balance}("");
    }
    
    function _purchase(
        uint256 _amount
    ) internal {
        require(totalSupply(VERSION) + _amount <= MAX_SUPPLY, "underground: MAX_SUPPLY reached");
        _mint(msg.sender, VERSION, _amount, "");
        emit Purchased(0, msg.sender, _amount);
    }


    function _verifySupply() internal view returns(bool) {
        return MAX_SUPPLY >= MAX_DEV_SUPPLY + MAX_PRESALE_SUPPLY + MAX_OPEN_SUPPLY + MAX_AUCTION_SUPPLY;
    }
}
