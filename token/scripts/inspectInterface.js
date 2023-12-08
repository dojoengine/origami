#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
// const starknet = require("starknet");

// Check for the required arguments
if (process.argv.length !== 3) {
    console.log("Usage: <script> <manifest-path>");
    process.exit(1);
}

// Extract paths from command-line arguments
const manifestPath = path.resolve(process.argv[2]);

const manifestContent = fs.readFileSync(manifestPath, "utf8");
const manifest = JSON.parse(manifestContent);


const shortType = (type) => {
    type=type.replace("core::starknet::class_hash::","");
    type=type.replace("core::starknet::contract_address::","");
    type=type.replace("core::starknet::","");
    
    type=type.replace("core::array::","");
    type=type.replace("core::integer::","");
    type=type.replace("core::","");
    return type
}


for (let abiItem of manifest.abi) {
    if (abiItem.type === "interface") {
        const functions = []

        console.log(`${abiItem.name} {`)
        for (let item of abiItem.items) {
            if (item.type === "function") {
                const inputs = item.inputs.map(i => `${i.name}: ${shortType(i.type)}`)
                const outputs = item.outputs.map(i => `${shortType(i.type)}`)
                functions.push(`${item.name}(${inputs.join(", ")}) -> (${outputs.join(", ")})`)
            }
        }

        console.log(`    ${functions.join('\n    ')}`)
        console.log(`}\n`)
    }
}




