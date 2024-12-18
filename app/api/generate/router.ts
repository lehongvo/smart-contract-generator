import { NextRequest, NextResponse } from "next/server";
import OpenAI from "openai";

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
                    content: `You are a Solidity smart contract generator. Generate complete, compilable smart contract code. 
                    For ERC20 tokens, always extend from ERC20. Include constructor parameters for name, symbol, and initial supply.
                    Do not include import statements or SPDX license.
                    The contract name must be 'TempContract'.`
                },
                { role: "user", content: message }
            ],
            temperature: 0.7,
            max_tokens: 2000
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