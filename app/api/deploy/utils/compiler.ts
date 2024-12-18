// app/api/deploy/utils/compiler.ts
import * as fs from "fs";
import * as path from "path";
import { exec } from "child_process";
import { promisify } from "util";
import { ethers } from "ethers";

const execAsync = promisify(exec);

// Initialize provider and wallet for Ronin testnet
const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);

export async function compileAndDeploy(sourceCode: string) {
    try {
        // Create temporary contract file
        const contractsDir = path.join(process.cwd(), 'contracts');
        const contractPath = path.join(contractsDir, 'TempContract.sol');

        if (!fs.existsSync(contractsDir)) {
            fs.mkdirSync(contractsDir, { recursive: true });
        }

        // Add SPDX and pragma
        const fullSourceCode = `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

${sourceCode}`;

        // Write contract code to file
        fs.writeFileSync(contractPath, fullSourceCode);

        // Run Hardhat compile command
        console.log('Compiling contract...');
        try {
            await execAsync('npx hardhat compile');
        } catch (compileError) {
            throw new Error(`Compilation failed: ${compileError}`);
        }

        const artifactPath = path.join(
            process.cwd(),
            'artifacts/contracts/TempContract.sol/TempContract.json'
        );

        if (!fs.existsSync(artifactPath)) {
            throw new Error('Compilation failed - no artifact generated');
        }

        const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));

        // Deploy using ethers
        console.log('Deploying contract...');
        const factory = new ethers.ContractFactory(
            artifact.abi,
            artifact.bytecode,
            wallet
        );

        const contract = await factory.deploy();
        await contract.deployed();

        // Clean up
        fs.unlinkSync(contractPath);

        return {
            address: contract.address,
            abi: artifact.abi,
            bytecode: artifact.bytecode,
            deploymentTransaction: contract.deployTransaction
        };
    } catch (error) {
        console.error('Error in compilation/deployment:', error);
        throw error;
    }
}