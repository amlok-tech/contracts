// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract SimpleToken is ERC20 {
    constructor() ERC20("USDT", "USDT") public {
        _mint(msg.sender, 21000000000e18);
    }
    
    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }
}
