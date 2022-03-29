// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./Access.sol";
import "./AbstractERC1155.sol";

contract underground is AbstractERC1155, Access {

    uint256 public SEASON;
    uint256 public seasonCount;

    enum Status {
        idle,
        whitelist,
        auction,
        open
    }

    struct Season {
        uint256 id;
        uint256 maxSupply;
        uint256 whitelistPrice;
        uint256 openPrice;
        DutchAuctionConfig dutchAuctionConfig;
        Status status;
        bytes32 merkleRoot;
    }

    struct DutchAuctionConfig {
        uint256 startPoint;
        uint256 startPrice;
        uint256 decreaseInterval;
        uint256 decreaseSize;
        uint256 numDecreases;
    }

    mapping(uint256 => Season) public seasons;
    mapping(uint256 => mapping(address => bool)) mintedPerWallet;
    event Purchased(uint256 indexed index, address indexed account, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _uri
    ) ERC1155(_uri) 
    {
        name_ = _name;
        symbol_ = _symbol;
        transferOwnership(tx.origin);
    }

    modifier verifyMint(uint256 _price) {
        require(tx.origin == msg.sender, "undergound: only eoa");
        require(!mintedPerWallet[SEASON][msg.sender], "undergound: already minted");
        require(msg.value >= _price, "undergound: invalid value sent");
        _;
    }

    function setStatus(uint256 _id, Status _status) external onlyAdmin {
        require(_id > 0 && _id <= seasonCount, "underground: invalid season id");
        seasons[_id].status = _status;
        if(_status == Status.auction) {
            // start the auction
            seasons[_id].dutchAuctionConfig.startPoint = block.timestamp;
        }
    }

    function setSeason(uint256 _id) public onlyAdmin {
        require(_id > 0 && _id <= seasonCount, "underground: invalid season id");
        SEASON = _id;
    }

    function createNewSeason(
        uint256 _maxSupply,
        uint256 _whitelistPrice,
        uint256 _openPrice,
        DutchAuctionConfig memory _dutchAuctionConfig,
        uint256 _expectedReserve,
        bytes32 _merkleRoot
    ) external onlyAdmin {
        seasonCount++;
        editSeason(seasonCount, _maxSupply, _whitelistPrice, _openPrice, _dutchAuctionConfig, _expectedReserve, _merkleRoot);
        setSeason(seasonCount);
    }

    function editSeason(
        uint256 _id,
        uint256 _maxSupply,
        uint256 _whitelistPrice,
        uint256 _openPrice,
        DutchAuctionConfig memory _dutchAuctionConfig,
        uint256 _expectedReserve,
        bytes32 _merkleRoot
    ) public onlyAdmin {
        require(_id > 0 && _id <= seasonCount, "underground: invalid season id");
        require(totalSupply(_id) <= seasons[_id].maxSupply, "undergound: invalid maxSupply");
        require(_dutchAuctionConfig.decreaseInterval > 0, "underground: zero decrease interval");
        unchecked {
            require(_dutchAuctionConfig.startPrice - _dutchAuctionConfig.decreaseSize * _dutchAuctionConfig.numDecreases == _expectedReserve, "underground: incorrect reserve");
        }

        seasons[_id] = Season(
            _id,
            _maxSupply,
            _whitelistPrice,
            _openPrice,
            _dutchAuctionConfig,
            Status.idle,
            _merkleRoot
        );
    }

    function devMint(uint256 _amount, address _to) external onlyOwner {
        require(totalSupply(SEASON) + _amount <= seasons[SEASON].maxSupply, "undergound: cap for season reached");
        _mint(_to, SEASON, _amount, "");
    }

    function devMintMultiple(address[] calldata _to) external onlyOwner {
        uint256 l = _to.length;
        require(totalSupply(SEASON) + l <= seasons[SEASON].maxSupply, "undergound: cap for season reached");

        for(uint256 i = 0; i < l; i++) {
            _mint(_to[i], SEASON, 1, "");
        }
    }

    function whitelistMint(bytes32[] calldata _merkleProof) external payable verifyMint(seasons[SEASON].whitelistPrice) {
        require(seasons[SEASON].status == Status.whitelist, "undergound: whitelist not started");

        bytes32 node = keccak256(abi.encodePacked(SEASON, msg.sender));
        require(
            MerkleProof.verify(_merkleProof, seasons[SEASON].merkleRoot, node),
            "underground: invalid proof"
        );
        _internalMint(1);
    }

    function auctionMint() external payable verifyMint(_cost(1)) {
        require(seasons[SEASON].status == Status.auction, "undergound: auction not started");
        _internalMint(1);
    }

    function openMint() external payable verifyMint(seasons[SEASON].openPrice) {
        require(seasons[SEASON].status == Status.open, "undergound: auction not started");
        _internalMint(1);
    }

    function _internalMint(uint256 _amount) internal {
        require(totalSupply(SEASON) + _amount <= seasons[SEASON].maxSupply, "undergound: cap for season reached");
        mintedPerWallet[SEASON][msg.sender] = true;

        _mint(msg.sender, SEASON, _amount, "");
        emit Purchased(SEASON, msg.sender, _amount);
    }

    function _cost(uint256 n) internal view returns (uint256) {
        DutchAuctionConfig storage cfg = seasons[SEASON].dutchAuctionConfig;
        return n * (cfg.startPrice - Math.min((block.timestamp - cfg.startPoint) / cfg.decreaseInterval, cfg.numDecreases) * cfg.decreaseSize);
    }

    function uri(uint256 _id) public view override returns (string memory) {
        require(exists(_id), "URI: nonexistent token");
        return string(abi.encodePacked(super.uri(_id), Strings.toString(_id)));
    }

    function setURI(string memory baseURI) external onlyOwner {
        _setURI(baseURI);
    }  

    function withdraw() external onlyOwner {
        owner().call{value: address(this).balance}("");
    }
}
