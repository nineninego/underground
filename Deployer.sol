// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./underground.sol";

contract Deployer {
    function deploy(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        address _recipient,
        bytes32 _salt
    ) public payable returns (address) {
        return address(new underground{salt: _salt}(_name, _symbol, _uri, _recipient));
    }
}
