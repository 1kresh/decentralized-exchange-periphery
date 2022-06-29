import { Wallet, Contract, providers } from 'ethers'
import { deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './utilities'

import SimswapFactory from '@simswap/core/build/SimswapFactory.json'
import ISimswapPool from '@simswap/core/build/ISimswapPool.json'

import ERC20 from '../../build/ERC20.json'
import WETH9 from '../../build/WETH9.json'
import SimswapRouter from '../../build/SimswapRouter.json'
import RouterEventEmitter from '../../build/RouterEventEmitter.json'

const overrides = {
  gasLimit: 99999999,
}

interface Fixture {
  token0: Contract
  token1: Contract
  WETH: Contract
  WETHPartner: Contract
  factory: Contract
  router: Contract
  routerEventEmitter: Contract
  pool: Contract
  WETHPool: Contract
}

export async function Fixture(provider: providers.Web3Provider, [wallet]: Wallet[]): Promise<Fixture> {
  // deploy tokens
  const tokenA = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)])
  const tokenB = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)])
  const WETH = await deployContract(wallet, WETH9)
  const WETHPartner = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)])

  // deploy
  const factory = await deployContract(wallet, SimswapFactory, [wallet.address])

  // deploy routers
  const router = await deployContract(wallet, SimswapRouter, [factory.address, WETH.address], overrides)

  // event emitter for testing
  const routerEventEmitter = await deployContract(wallet, RouterEventEmitter, [])

  // initialize
  await factory.createPool(tokenA.address, tokenB.address)
  const poolAddress = await factory.getPool(tokenA.address, tokenB.address)
  const pool = new Contract(poolAddress, JSON.stringify(ISimswapPool.abi), provider).connect(wallet)

  const token0Address = await pool.token0()
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA

  await factory.createPool(WETH.address, WETHPartner.address)
  const WETHPoolAddress = await factory.getPair(WETH.address, WETHPartner.address)
  const WETHPool = new Contract(WETHPoolAddress, JSON.stringify(ISimswapPool.abi), provider).connect(wallet)

  return {
    token0,
    token1,
    WETH,
    WETHPartner,
    factory,
    router,
    routerEventEmitter,
    pool,
    WETHPool,
  }
}
