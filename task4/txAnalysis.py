import asyncio
import aiohttp
from web3 import Web3
import time
import json
from datetime import datetime

# Story Network RPC URL
story_rpc_url = "https://story-testnet.nodeinfra.com"
web3 = Web3(Web3.HTTPProvider(story_rpc_url))

# Contract address
CONTRACT_ADDRESS = "0xCCcCcC0000000000000000000000000000000001"

# Method signature
METHOD_SIGNATURE = "0x8f37ec19"

async def get_block(session, block_number):
    payload = {
        "jsonrpc": "2.0",
        "method": "eth_getBlockByNumber",
        "params": [hex(block_number), True],
        "id": 1
    }
    async with session.post(story_rpc_url, json=payload) as response:
        result = await response.json()
        return result['result']

def parse_transaction(tx):
    return {
        'tx_hash': tx['hash'],
        'block_number': int(tx['blockNumber'], 16),
        'from': tx['from'],
        'to': tx['to'],
        'value': int(tx['value'], 16),
        'gas_price': int(tx['gasPrice'], 16),
        'gas': int(tx['gas'], 16),
        'nonce': int(tx['nonce'], 16),
        'input_data': tx['input']
    }

async def process_block(session, block_number):
    block = await get_block(session, block_number)
    relevant_txs = []
    if block and 'transactions' in block:
        for tx in block['transactions']:
            if (tx.get('to') and 
                tx['to'].lower() == CONTRACT_ADDRESS.lower() and 
                tx['input'].startswith(METHOD_SIGNATURE)):
                relevant_txs.append(parse_transaction(tx))
    return relevant_txs

async def analyze_transactions(start_block, end_block, batch_size=100):
    all_relevant_txs = []
    total_blocks = end_block - start_block + 1
    processed_blocks = 0

    async with aiohttp.ClientSession() as session:
        for batch_start in range(start_block, end_block + 1, batch_size):
            batch_end = min(batch_start + batch_size - 1, end_block)
            tasks = [process_block(session, block_number) for block_number in range(batch_start, batch_end + 1)]
            results = await asyncio.gather(*tasks)
            for txs in results:
                all_relevant_txs.extend(txs)
            
            processed_blocks += batch_size
            progress = (processed_blocks / total_blocks) * 100
            print(f"Progress: {progress:.2f}% (Block {batch_end}/{end_block})")

    return all_relevant_txs

def save_to_file(data, filename):
    with open(filename, 'w') as f:
        json.dump(data, f, indent=2)

async def main():
    if not web3.is_connected():
        print("Unable to connect to the Story Network.")
        return

    try:
        latest_block = web3.eth.block_number
        print(f"Current Story Network block height: {latest_block}")
        
        start_block = int(input("Enter the starting block number: "))
        end_block = int(input("Enter the ending block number (0 for latest block): "))
        
        if end_block == 0:
            end_block = latest_block
        
        print(f"Analyzing transactions from block {start_block} to {end_block}...")
        start_time = time.time()
        
        relevant_txs = await analyze_transactions(start_block, end_block)
        
        end_time = time.time()
        duration = end_time - start_time
        
        print(f"\nResults:")
        print(f"Number of relevant transactions found: {len(relevant_txs)}")
        print(f"Analyzed block range: {start_block} - {end_block}")
        print(f"Time taken: {duration:.2f} seconds")

        # Save results to a file
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"story_tx_analysis_{timestamp}.json"
        save_to_file(relevant_txs, filename)
        print(f"Detailed results saved to {filename}")

        # Display sample of transactions
        if relevant_txs:
            print("\nSample transaction details:")
            sample_tx = relevant_txs[0]
            print(json.dumps(sample_tx, indent=2))
    
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    asyncio.run(main())