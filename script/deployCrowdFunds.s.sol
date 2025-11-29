// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {CrowdFunds} from "src/CrowdFunds.sol";

contract deployCrowdFunds is Script {
    // Deployment script for crowdfunds contract
    function run() external returns (CrowdFunds) {
        vm.broadcast();
        CrowdFunds cf = new CrowdFunds(10 ether, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, "proposal", 120, 0.5 ether);

        vm.stopBroadcast();
        return cf;
    }
}

