#!/usr/bin/env node

// Generate a starknet::interface from a sozo artifact abi

const fs = require("fs");
const path = require("path");

// Check for the required arguments
if (process.argv.length !== 3) {
    console.log("Usage: <script> <artifact-path>");
    process.exit(1);
}

// Extract paths from command-line arguments
const contractPath = process.argv[2]
const manifestPath = path.resolve(contractPath);

const manifestContent = fs.readFileSync(manifestPath, "utf8");
const manifest = JSON.parse(manifestContent);


const shortType = (type) => {
    type = type.replace("core::starknet::class_hash::", "");
    type = type.replace("core::starknet::contract_address::", "");
    type = type.replace("core::starknet::", "");

    type = type.replace("core::array::", "");
    type = type.replace("core::integer::", "");
    type = type.replace("core::", "");

    type = type.replace("dojo::world::", "");

    return type
}

const functionToString = (item) => {
    const tState = item.state_mutability === "external" ? "ref self: TState" : "self: @TState";
    const inputs = item.inputs.map(i => `${i.name}: ${shortType(i.type)}`)
    const outputs = item.outputs.map(i => `${shortType(i.type)}`)
    return `fn ${item.name}(${tState}, ${inputs.join(", ")})${outputs.length > 0 ? " -> " : ""}${outputs.join(", ")};`
}

const contractName = contractPath.split("::").pop().replace(".json", "");
console.log(`\n\nuse starknet::{ContractAddress, ClassHash};`);
console.log(`use dojo::world::IWorldDispatcher;`);
console.log(`\n#[starknet::interface]`)
console.log(`trait I${contractName}<TState> {`)

const functionsWithoutInterface = []
const l1Handlers = []

for (let abiItem of manifest.abi) {
    if (abiItem.type === "interface") {
        const interfaceName = abiItem.name.split("::").pop()
        console.log(`    // ${interfaceName}`)

        const functions = []
        for (let item of abiItem.items.sort((a, b) => a.name > b.name ? 1 : -1)) {
            if (item.type === "function") {
                functions.push(functionToString(item))
            }
        }
        console.log(`    ${functions.join('\n    ')}\n`)
    }
    if (abiItem.type === "function") {
        functionsWithoutInterface.push(functionToString(abiItem))
    }
    if (abiItem.type === "l1_handler") {
        l1Handlers.push(`#[l1_handler]\n${functionToString(abiItem)}`)
    }

}

console.log(`    // WITHOUT INTERFACE !!!`)
console.log(`    ${functionsWithoutInterface.join('\n    ')}\n`)

console.log(`}\n`)

console.log(`// L1 Handlers`)
console.log(`${l1Handlers.join('\n    ')}\n`)



