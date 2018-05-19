pragma solidity ^0.4.23;

import "./bitwich.sol";

contract BitWichLoom is BitWich {
    // 0.002 sell price, 0.001 buy price
    constructor()
            BitWich(640, 1250, "LOOM", 0xA4e8C3Ec456107eA67d3075bF9e3DF3A75823DB0) public {
    }
}
