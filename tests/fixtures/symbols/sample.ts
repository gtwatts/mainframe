import { Request, Response } from 'express';
import type { Config } from './types';

export interface UserProfile {
    id: string;
    name: string;
    email?: string;
}

export type UserId = string;

export enum Status {
    Active = 'active',
    Inactive = 'inactive',
}

export class UserController {
    constructor(private service: UserService) {}

    async handleGet(req: Request, res: Response): Promise<void> {
        const user = await this.service.get(req.params.id);
        res.json(user);
    }
}

export function createApp(config: Config): Express {
    return express();
}

export const fetchUsers = async (limit: number): Promise<UserProfile[]> => {
    return [];
};

const internalHelper = (x: number): number => x * 2;

export default class AppServer {
    start(): void {}
}

export { UserController as Controller };
