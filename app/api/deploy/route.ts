// app/api/deploy/route.ts
import { NextRequest, NextResponse } from "next/server";
import { compileAndDeploy } from "./utils/compiler";

export async function POST(req: NextRequest) {
    try {
        const { contractCode } = await req.json();

        if (!contractCode) {
            return NextResponse.json(
                { error: 'Contract code is required' },
                { status: 400 }
            );
        }

        const deploymentResult = await compileAndDeploy(contractCode);

        return NextResponse.json({
            success: true,
            data: deploymentResult
        });

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