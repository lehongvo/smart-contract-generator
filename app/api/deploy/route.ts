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

    } catch (error) {
        console.error('Error:', error);
        return NextResponse.json(
            {
                error: 'Internal server error',
            },
            { status: 500 }
        );
    }
}