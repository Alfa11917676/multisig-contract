// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";
import { Multisig } from "../src/Multisig.sol";

contract DeployScript is Script {
    function run() public {
        address owner0 = vm.envOr("MULTISIG_OWNER_0", vm.addr(1));
        address owner1 = vm.envOr("MULTISIG_OWNER_1", vm.addr(2));

        vm.startBroadcast();
        Multisig multisig = new Multisig(owner0, owner1);
        vm.stopBroadcast();

        console.log("Multisig deployed at", address(multisig));
        console.log("Owner 0:", multisig.owners(0));
        console.log("Owner 1:", multisig.owners(1));
    }
}
