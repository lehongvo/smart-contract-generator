import { NextRequest, NextResponse } from "next/server";
import OpenAI from "openai";


/*
* This API route generates a Solidity smart contract using OpenAI's GPT-3 model.
*/
const openai = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY,
});

export async function POST(req: NextRequest) {
    try {
        const { message } = await req.json();

        if (!message) {
            return NextResponse.json(
                { error: 'Message is required' },
                { status: 400 }
            );
        }

        const completion = await openai.chat.completions.create({
            model: "gpt-3.5-turbo",
            messages: [
                {
                    role: "system",
                    content: `You are an expert Solidity smart contract generator and auditor. Never use markdown formatting or code block syntax.
        
        Generate advanced, secure ERC20 contracts with these enterprise-level features:
        
        SECURITY FEATURES:
        - Reentrancy guards for all external calls
        - Integer overflow protection using SafeMath
        - Access control with role-based permissions
        - Emergency pause mechanisms
        - Blacklist and whitelist functionalities
        - Rate limiting for transactions
        
        TOKENOMICS AND FEATURES:
        - Dynamic tax system (buy/sell/transfer taxes)
        - Anti-bot and anti-snipe mechanisms
        - Auto liquidity generation
        - Reflection rewards to holders
        - Vesting schedules for team/presale tokens
        - Max wallet and transaction limits
        - Token buyback and burn mechanisms
        - Flash loan attack prevention
        
        ADVANCED FUNCTIONS:
        - Governance integration
        - Staking capabilities
        - Token locking
        - Multi-signature requirements
        - Upgradeability patterns
        - Cross-chain bridge support
        - Batch transfer capabilities
        
        OPTIMIZATION:
        - Gas-optimized code patterns
        - Efficient storage layouts
        - Minimal external calls
        - Optimized loops and arrays
        
        FORMAT:
        - Comprehensive NatSpec documentation
        - Clear function grouping
        - Extensive event logging
        - Security-focused modifiers
        - Detailed error messages
        
        The contract must:
        - Be named 'TempContract'
        - Extend OpenZeppelin's ERC20
        - Include clear inline documentation
        - Follow latest Solidity best practices
        
        Do not include any markdown formatting or code block syntax. Generate only clean Solidity code.`
                },
                {
                    role: "user",
                    content: message
                }
            ],
            temperature: 0.7,
            max_tokens: 4000
        });

        const contractCode = completion.choices[0].message?.content;

        if (!contractCode) {
            return NextResponse.json(
                { error: 'Failed to generate contract code' },
                { status: 500 }
            );
        }

        return NextResponse.json({ contractCode });

    } catch (error: any) {
        console.error('Error:', error);
        return NextResponse.json(
            {
                error: 'Internal server error',
                details: process.env.NODE_ENV === 'development' ? error.message : undefined
            },
            { status: 500 }
        );
    }
}