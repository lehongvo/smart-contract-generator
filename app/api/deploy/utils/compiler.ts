import * as fs from "fs";
import * as path from "path";
import { exec } from "child_process";
import { promisify } from "util";
import { ethers } from "ethers";

const execAsync = promisify(exec);

// Initialize provider and wallet for Ronin testnet
const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);

export async function compileAndDeploy(sourceCode: string) {
    try {
        // Create directories
        const contractsDir = path.join(process.cwd(), 'contracts');
        const artifactsDir = path.join(process.cwd(), 'artifacts/contracts');

        if (!fs.existsSync(contractsDir)) {
            fs.mkdirSync(contractsDir, { recursive: true });
        }
        if (!fs.existsSync(artifactsDir)) {
            fs.mkdirSync(artifactsDir, { recursive: true });
        }

        // Extract contract name correctly using regex
        const contractNameMatch = sourceCode.match(/contract\s+(\w+)\s*{/);
        if (!contractNameMatch) {
            throw new Error('Could not detect contract name');
        }
        const contractName = contractNameMatch[1];
        console.log('Detected contract name:', contractName);

        // Write contract file with correct name
        const contractFileName = `${contractName}.sol`;
        const contractPath = path.join(contractsDir, contractFileName);
        fs.writeFileSync(contractPath, sourceCode);

        // Compile
        console.log('Compiling contract...');
        const compileResult = await execAsync('npx hardhat compile --force');
        console.log('Compile output:', compileResult.stdout);

        // Check artifact with correct path
        const artifactPath = path.join(
            process.cwd(),
            'artifacts/contracts',
            contractFileName,
            `${contractName}.json`
        );

        if (!fs.existsSync(artifactPath)) {
            console.error('Expected artifact path:', artifactPath);
            console.error('Contract name:', contractName);
            throw new Error(`Artifact not found at ${artifactPath}`);
        }

        const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));

        // Deploy using ethers v6
        console.log('Deploying contract...');
        const factory = new ethers.ContractFactory(
            artifact.abi,
            artifact.bytecode,
            wallet
        );

        const contract = await factory.deploy();
        await contract.waitForDeployment();

        // Clean up
        fs.unlinkSync(contractPath);

        const deployedAddress = await contract.getAddress();

        return {
            address: deployedAddress,
            abi: artifact.abi,
            bytecode: artifact.bytecode,
            deploymentTransaction: contract.deploymentTransaction()
        };
    } catch (error) {
        console.error('Full error:', error);
        throw error;
    }
}