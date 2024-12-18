// app/page.tsx
'use client';

import { useState } from 'react';
import { Loader2 } from 'lucide-react';
import { ArrowUpRight } from 'lucide-react';

type DeploymentResultType = {
  deploymentTransaction: {
    hash: string;
    gasLimit: string;
    gasPrice: string;
  };
  contractAddress: string;
  address: string;
  abi: object[];
}

export default function ContractGenerator() {

  const [prompt, setPrompt] = useState('');
  const [loading, setLoading] = useState(false);
  const [generatedContract, setGeneratedContract] = useState('');
  const [deploymentResult, setDeploymentResult] = useState<DeploymentResultType | null>(null);
  const [error, setError] = useState('');

  const generateContract = async () => {
    if (!prompt.trim()) return;

    try {
      setLoading(true);
      setError('');
      setGeneratedContract('');
      setDeploymentResult(null);

      console.log('Sending request to /api/generate');

      const response = await fetch('/api/generate', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ message: prompt }),
      });

      console.log('Response status:', response.status);
      const responseText = await response.text();
      console.log('Response text:', responseText);

      const data = JSON.parse(responseText);
      if (data.lenght === 0) {
        console.error('Failed to parse response:', responseText);
        throw new Error('Invalid server response');
      }

      if (!response.ok) {
        throw new Error(data.error || data.details || 'Failed to generate contract');
      }

      setGeneratedContract(data.contractCode);
    } catch (err) {
      console.error('Generation error:', err);
      setError('Failed to generate contract');
    } finally {
      setLoading(false);
    }
  };

  const deployContract = async () => {
    if (!generatedContract) return;

    try {
      setLoading(true);
      setError('');

      const response = await fetch('/api/deploy', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ contractCode: generatedContract }),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || data.details || 'Failed to deploy contract');
      }

      console.log('Deployment result:', data.data);

      setDeploymentResult(data.data);
    } catch (err) {
      console.error('Deployment error:', err);
      setError("Failed to deploy contract, please check the console for more details");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="container mx-auto p-6 max-w-4xl">
      <div className="bg-white rounded-lg shadow-lg p-6 mb-6">
        <h1 className="text-2xl font-bold mb-2 text-gray-900">Smart Contract Generator</h1>
        <p className="text-gray-700 mb-4">
          Describe the smart contract you want to create and we will generate it for you
        </p>
        <textarea
          placeholder="Example: Create an ERC20 token with initial supply of 1000000"
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          className="w-full p-2 border rounded-md min-h-32 mb-4 text-gray-900 placeholder-gray-500"
        />
        <button
          onClick={generateContract}
          disabled={loading || !prompt.trim()}
          className="w-full bg-blue-500 text-white p-2 rounded-md disabled:bg-gray-300 flex items-center justify-center"
        >
          {loading && !generatedContract ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Generating Contract...
            </>
          ) : (
            'Generate Contract'
          )}
        </button>
      </div>

      {error && (
        <div className="bg-red-50 border-l-4 border-red-500 p-4 mb-6">
          <p className="text-red-700">{error}</p>
        </div>
      )}

      {generatedContract && (
        <div className="bg-white rounded-lg shadow-lg p-6 mb-6">
          <h2 className="text-xl font-bold mb-4 text-gray-900">Generated Contract</h2>
          <pre className="bg-gray-50 p-4 rounded-md overflow-x-auto mb-4">
            <code className="text-gray-900">{generatedContract}</code>
          </pre>
          <button
            onClick={deployContract}
            disabled={loading}
            className="w-full bg-green-500 text-white p-2 rounded-md disabled:bg-gray-300 flex items-center justify-center"
          >
            {loading ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Deploying Contract...
              </>
            ) : (
              'Deploy Contract'
            )}
          </button>
        </div>
      )}

      {deploymentResult && (
        <div className="space-y-6">
          <div className="bg-white rounded-lg shadow-lg p-6">
            <h2 className="text-xl font-bold mb-4 text-gray-900">Deployment Details</h2>
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div className="space-y-1">
                  <p className="font-medium text-sm text-gray-900">Contract Address: {deploymentResult.contractAddress}</p>
                  <div className="flex items-center space-x-2">
                    <p className="font-mono text-sm text-blue-600 truncate text-c">
                      {deploymentResult.address}
                    </p>
                    <button
                      onClick={() => window.open(`https://saigon-app.roninchain.com/address/${deploymentResult.contractAddress}`, '_blank')}
                      className="p-1 hover:bg-gray-00 rounded"
                    >
                      <ArrowUpRight size={16} className="text-gray-500" />
                    </button>
                  </div>
                </div>
              </div>

              <div className="space-y-1">
                <p className="font-medium text-sm text-gray-600">Transaction Hash</p>
                <div className="flex items-center space-x-2">
                  <p className="font-mono text-sm text-blue-600 truncate">
                    {deploymentResult.deploymentTransaction.hash}
                  </p>
                  <button
                    onClick={() => window.open(`https://saigon-app.roninchain.com/tx/${deploymentResult.deploymentTransaction.hash}`, '_blank')}
                    className="p-1 hover:bg-gray-100 rounded"
                  >
                    <ArrowUpRight size={16} className="text-gray-500" />
                  </button>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1">
                  <p className="font-medium text-sm text-gray-600">Gas Limit</p>
                  <p className="font-mono text-sm  text-gray-900">{deploymentResult.deploymentTransaction.gasLimit}</p>
                </div>
                <div className="space-y-1">
                  <p className="font-medium text-sm text-gray-600">Gas Price</p>
                  <p className="font-mono text-sm  text-gray-900">{deploymentResult.deploymentTransaction.gasPrice}</p>
                </div>
              </div>
            </div>
          </div>

          <div className="bg-white rounded-lg shadow-lg p-6">
            <h2 className="text-xl font-bold mb-4 text-gray-900">Contract ABI</h2>
            <pre className="bg-gray-50 p-4 rounded-md overflow-x-auto">
              <code className="text-gray-900">{JSON.stringify(deploymentResult.abi, null, 2)}</code>
            </pre>
          </div>
        </div>
      )}
    </div>
  );
}