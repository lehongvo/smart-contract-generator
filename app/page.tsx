// app/page.tsx
'use client';

import { useState } from 'react';
import { Loader2 } from 'lucide-react';

export default function ContractGenerator() {
  const [prompt, setPrompt] = useState('');
  const [loading, setLoading] = useState(false);
  const [generatedContract, setGeneratedContract] = useState('');
  const [deploymentResult, setDeploymentResult] = useState<any>(null);
  const [error, setError] = useState('');

  const generateContract = async () => {
    if (!prompt.trim()) return;

    try {
      setLoading(true);
      setError('');
      setGeneratedContract('');
      setDeploymentResult(null);

      const response = await fetch('/api/generate', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ message: prompt }),
      });

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || errorData.details || 'Failed to generate contract');
      }

      const data = await response.json();
      setGeneratedContract(data.contractCode);
    } catch (err: any) {
      console.error('Generation error:', err);
      setError(err.message || 'Failed to generate contract');
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

      setDeploymentResult(data.data);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="container mx-auto p-6 max-w-4xl">
      <div className="bg-white rounded-lg shadow-lg p-6 mb-6">
        <h1 className="text-2xl font-bold mb-2 text-gray-900">Smart Contract Generator</h1>
        <p className="text-gray-700 mb-4">
          Describe the smart contract you want to create and we'll generate it for you
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
            <div className="space-y-2 text-gray-900">
              <p><strong>Contract Address:</strong> {deploymentResult.contractAddress}</p>
              <p><strong>Transaction Hash:</strong> {deploymentResult.deploymentTransaction.hash}</p>
              <p><strong>Gas Limit:</strong> {deploymentResult.deploymentTransaction.gasLimit}</p>
              <p><strong>Gas Price:</strong> {deploymentResult.deploymentTransaction.gasPrice}</p>
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